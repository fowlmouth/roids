import enet, strutils, streams,
  private/pkt_tools, private/packets,
  fowltek/maybe_t

if enet.initialize() != 0:
  quit "Could not initialize ENet"

type
  TPacketHandler* = proc(C:PClient; P:PPacket)
  TScPacketVT = seq[TPacketHandler]

  pclient* = var tclient
  TClient* = object
    host: PHost
    peer*: PPeer
    address: enet.TAddress
    running:bool
    
    packetHandlers*: TScPacketVT
    onAuthenticate: proc() {.closure.}
    authenticated: TMaybe[int]

var defVT: TScPacketVT
proc initClient (address: string, port: int): TClient =
  result.host = createHost(nil, 1, packets.packetChannels, 0,0)
  if result.host.isnil:
    raise newException(EEnet, "Could not create client")
  if setHost(result.address.addr, address) != 0:
    raise newException(EENet, "Could not set host")
  result.address.port = port.cushort
  result.packetHandlers = defVT



proc login (C: PClient; user,pass: string) =
  var p = initOpkt(32)
  p << csLogin(user:user, pass:pass)
  c.peer.send( 0.cuchar, p, flagReliable )

proc send_pubchat (C:PClient; msg:string) =
  var p = initOpkt(512)
  p << csPubchat(msg:msg)
  c.peer.send( 0.cuchar, p )

import private/common

newSeq defVT, sc_id_max+1

defVT[sc_serverinfo_id] = proc(C:PClient; P:PPacket) =
      var v: sc_serverinfo
      p >> v
      assert v.version == (0u8, 0u8, 1u8)
      
      echo "Correct version."
defVT[sc_loginresponse_id] = proc(C:PClient; P:PPacket) =
      var r: sc_login_response
      p >> r
      
      if r.goodLogin:
        # yay we are logged in, thats kewl
        c.authenticated = just(r.client_id.int)
        if not c.onAuthenticate.isNil: c.onAuthenticate()
        echo "Authenticated, player #",r.client_id
      else:
        echo "[Warning] Not authenticated: ", r.msg
defVT[sc_pubchat_id] = proc(C:PClient; P:PPacket)=

      var c: sc_pubchat
      p >> c
      
      echo "<$1> $2".format(c.author, c.msg)
defVT[sc_notification_id] = proc(C:PClient; P:PPacket)=      
      var n: sc_notification
      p >> n
      
      echo "[Server] ", n.msg
defVT[sc_shutdown_id] = proc(C:PClient; P:PPacket) =
      echo "Server shutting down, disconnecting."
      c.running = false

proc dispatchPacket* (C:PCLIENT;P:PPacket) =
  while p.referenceCount.debugP("packet reference count ") < p.dataLength:
    var id: sc_id_ty
    p >> id
    if id in 1 .. sc_id_max and not c.packetHandlers[id.int].isNil:
      c.packetHandlers[id.int](c, p)



proc connect* (C: Var TClient; timeout = 500; maxTries = 5): bool =
  c.peer = c.host.connect(c.address.addr, 2,0)
  if c.peer.isNil:
    raise newException(EEnet, "No available peers")
  
  var 
    tries = 0
    event: enet.TEvent
  while tries < maxTries:
    echo "Connection attempt $#/$#".format(tries+1, maxTries)
    if c.host.hostService(event, timeout.cuint) > 0 and event.kind == EvtConnect:
      echo "Connected "
      c.peer = event.peer
      
      login(c, "foo","bar")
      
      c.running = true
      return true
      
    tries.inc
  
  c.peer.reset

proc poll* (C:PClient; timeout = 500): bool =
  var event: TEvent
  if c.host.hostService(event.addr, timeout.cuint) >= 0:
    result = true
    case event.kind
    of EvtReceive:

      dispatchPacket c,event.packet
      event.packet.referenceCount = 0
      destroy event.packet
      
    of EvtDisconnect:
      
      echo "Disconnected"
      event.peer.data = nil
      result = false
      
    of EvtNone: discard
      
    else:
      echo repr(event)

proc run (C: var TClient) =
  try:
    while c.running and c.poll: 
      #
  finally:
    c.running = false
    
proc destroy* (C: var TClient) =
  c.host.destroy


var c = initClient("localhost", 8024)
if not c.connect:
  echo "Failed to connect."
  quit 0
c.run

c.destroy()


