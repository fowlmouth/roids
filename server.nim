
import 
  enet, strutils, json, tables,
  
  private/room, private/room_interface, private/common,
  private/pkt_tools, private/packets, 
  private/gamedat,private/components,
  
  fowltek/entitty,
  fowltek/idgen

if enet.initialize() != 0:
  quit "Could not initialize ENet"

const
  ServerVersion = (0'u8, 0'u8, 1'u8)
type
  TPktRecv* = proc(S:PServer; P:PPeer; pkt:PPacket)

  PServer = var TServer
  TServer = object
    address: enet.TAddress
    host: PHost
    room: PRoom
    gamedata: PGameData
    name: string
    running: bool
    clients*: TTable[string, int]
    
    packetHandlers*: seq[TPktRecv]
    pubchat_backlog*: array[100,sc_pubchat]
let
  defaultSettings = %{
    "port": %8024, 
    "name": %"server", 
    "zone": %"data/alphazone"
  }

  settingsSchema = %{
    "type": %"object",
    "fields": %{
      "port": %{"type": %"int", "required": %true},
      "name": %{"type": %"str", "required": %true},
      "zone": %{"type": %"str", "required": %true},
    }
  }

proc validate* (schema, node: PJsonNode): bool =
  case schema["type"].str
  of "object":
    for key, val in schema["fields"]:
      let
        required = val["required"].bval
      if required and not node.hasKey(key):
        return false
      if node.hasKey(key):
        case val["type"].str
        of "int":
          if node[key].kind != jINT:
            return false
        of "str","string":
          if node[key].kind != jSTRING:
            return false
        of "obj","object":
          if node[key].kind != jOBJECT:
            return false


var callbacks = newSeq[TPktRecv](cs_id_max+1)

proc initServer* (data = defaultSettings): TServer =
  result.address = enet.TAddress(host: EnetHostAny, port: data["port"].num.cushort)
  result.name = data["name"].str
  
  result.gamedata = data["zone"].str.loadGamedata
  
  result.room = newRoom(result.gamedata, result.gamedata.firstRoom)
  
  result.packetHandlers = callbacks
  
  result.host = enet.createHost(
    result.address.addr, 32, packets.packet_channels, 0, 0 )
  if result.host.isnil:
    raise newException(EIO, "Could not create server")
  
  result.running = true
  
  when defined(debug):
    echo "Server opened"


let clientType = dom.changeComponents( room.playerType, add = components(EnetPeer) )
proc newClient* (S:PServer; user:string; peer:PPeer): int =
  result = s.room.joinPlayer(user, clientType)
  peer.data = cast[pointer](result)
  s.room.getEnt(result)[enetPeer].p = peer
  
  



proc entID* (P:PPEER): int {.inline.} = cast[int](p.data)

proc handle_pub_chat (S:PServer; P:PPeer; pkt:PPacket) =
    var chat: cs_pubchat
    pkt >> chat
    
    if chat.msg.len > 512:
      chat.msg.setLen 512
    
    let client = p.entID.int32
    if client > 0:
      echo "<$#> $#".format(
        s.room.getEnt(client.int).getName, chat.msg
      )
      var op = initOpkt(sizeof(int8) + sizeof(int32) + sizeof(int16) + len(chat.msg))
      op << sc_pubchat(author: client, msg: chat.msg)
      s.host.broadcast 1.cuchar, op
    
    else:
      echo "[Warning] Chat attempt from unauthorized client. ", chat
      var op = initOpkt(128)
      op << sc_notification(msg: "You cannot send public chat, you are not logged in.")
      p.send 1.cuchar, op, flagReliable

proc handleSyncComponent* (S:PServer; P:PPeer; pkt:PPacket) =
    var sc: cs_SYnc_COmponent
    pkt >> sc
    
    # make sure this client owns sc.entity
    
    let client = cast[int](p.data)
    template ent : expr = s.room.getEnt(sc.entity.int)
    
    if  client > 0 and ent.id > 0 and 
        ent.hasComponent(ClientControlled) and 
        ent[ClientControlled].client == client:
      
      var o = initOpkt(sizeof(int8) + sizeof(int32)*2 + len(pkt.data))
      o << sc_sync_component_id
      o << sc.entity
      o << sc.component
      o << sc.data
      s.host.broadcast 0.cuchar, o

proc handle_login (S: PServer; P: PPeer; pkt: PPacket) =
    var L: cslogin
    pkt >> L
    
    var lr = scLoginResponse()
    
    if p.data.isNil:
      let c = s.newClient(L.user, p)
      lr.goodLogin = true
      lr.clientID = c.int32
      
      var pkt = initOpkt(8)
      pkt << lr
      s.room.getEnt(c)[enetPeer].p.send 0.cuchar, pkt, flagReliable
      
    else:
      # user is already logged in
      var pkt = initOpkt(32)
      lr.goodLogin = false
      lr.msg = "You are already logged in as $#" % s.room.getEnt(p.entID).getName
      pkt << lr
      
      p.send pc_serv, pkt, flagReliable.cint
      
    echo "Login attempt from $#: $#".format(l.user, lr)

callbacks[ cs_login_id.int ] = handle_login
callbacks[ cs_sync_component_id.int ] = handle_sync_component
callbacks[ cs_pubchat_id.int ] = handle_pub_chat

proc dispatchPkt (S:PSERVER; P:PPEER; ID:CS_ID_TY; PKT:PPACKET) {.inline.} =
  if id in 1 .. cs_id_max and not s.packetHandlers[id.int].isNil:
    s.packetHandlers[id.int]( s,p,pkt )
    
  else:
    when defined(Debug):
      echo "[Warning] unhandled packet type ", id


proc recvPacket (S:PSERVER; P:PPEER; PKT:PPACKET){.INLINE.}=
  while pkt.referenceCount < pkt.dataLength:
    var id: cs_id_ty
    pkt >> id
    try:
      s.dispatchPkt p, id, pkt
    except EIO:
      echo "[Warning] ", getCurrentExceptionMsg()
      break

proc removeClient (S:VAR TSERVER; CLIENT:INT) =
  assert s.room.getEnt(client).id == client
  # send client disconnected to everybody
  var pkt = initOpkt(64)
  pkt << sc_client_quit(client: client.int32)
  s.host.broadcast pc_room, pkt, flagReliable.cint
  s.room.doom client

proc run (S:VAR TSERVER) =
  var 
    event: enet.TEvent
    sv_pkt = sc_server_info(version: serverVersion)
  
  while s.running and s.host.hostService(event.addr, 60) >= 0:
    case event.kind 
    of evtConnect:
      echo "New client from $1:$2".format(
        event.peer.address.host, event.peer.address.port)
      
      var pkt = initOpkt(128)
      # send server info
      pkt << sv_pkt
      # send hello
      pkt << sc_notification(msg: "Welcome to a server.")
      
      if event.peer.send(0.cuchar, pkt, flagReliable) != 0:
        echo "Failed to send server info..?"

    of evtDisconnect:

      echo "Peer disconnectd!"
      
      if not event.peer.data.isNil:
        let client = cast[int](event.peer.data)
        
        echo "Client $# (#$#) disconnected".format(client, s.Room.getEnt(client).getName)
        
        s.removeClient client
        
        event.peer.data = nil
    
    of evtReceive:
      
      s.recvPacket ( event.peer, event.packet )
      event.packet.referenceCount = 0
      destroy event.packet
    
    of evtNone:
      discard
    
    else:
      echo event.kind

proc destroy (S:VAR TSERVER) =
  s.host.destroy


var s = initServer()

setControlCHook do{.noconv.}:
  echo "^C intercepted."
  quit 0

s.run
s.destroy

enet.deinitialize()

echo "Server halted."
