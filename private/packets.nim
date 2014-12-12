import enet, private/pkt_tools

type
  cs_login * = object
    user*: string
    pass*:string

  sc_serverinfo * = object
    version*: tuple[major, minor, patch: uint8]
    
  sc_loginresponse * = object
    case goodLogin*: bool
    of true:
      client_id*: int32
    else:
      msg*: string    

  cs_pubchat* = object
    msg*:string
  sc_pubchat* = object
    author*: int32
    msg*: string
  sc_notification* = object
    msg*:string

type EEnet* = object of EBase

type
  cs_sync_component* = object
    entity*,component*: int32
    data*: seq[byte]
  sc_sync_component* = object
    pkt*: cs_sync_component

  TClientListItem* = object
    id*: int32
    name*: string
  sc_client_list* = object
    clients*: seq[TClientListItem]
  sc_client_quit* = object
    client*: int32

import macros
macro id_pkts* (args:varargs[expr]): stmt {.immediate.}=
  ## id_pkts(sc, sc_a,sc_b,sc_c) 
  ## defines sc_id_ty as uint8, uint16 or uint32
  ## defines sc_a_id, sc_b_id, sc_c_id as sc_id_ty starting from 1 

  let cs = callsite()
  let ty = $cs[1]
  
  result = newStmtList()
  
  let n_packets = len(cs) - 2
  var this_id_type: PNimrodNode
  if n_packets < uint8.high.int:
    this_id_type = ident("uint8")
  elif n_packets < uint16.high.int:
    this_id_type = ident("uint16")
  else:
    this_id_type = ident("uint32")
  
  result.add newNimNode(nnkTypeSection).add(
    newNimNode(nnkTypeDef).add(
      ident(ty & "_ID_TY").postfix("*"),
      newEmptyNode(),
      this_id_type
    )
  )
  
  let csection = newNimNode(nnkConstSection)
  csection.add newNimnode(nnkConstDef).add(
    ident(ty & "_id_max").postfix("*"),
    newEmptyNode(),
    newIntLitNode(n_packets)
  )
  
  var id = 1
  for idx in 2 .. <len(cs):
    let arg = cs[idx]
    csection.add newNimNode(nnkConstDef).add(
        ident($arg & "_id").postfix("*"), this_id_type, newIntLitNode(id)
    )
    
    inc id 
    
  result.add csection
  
  when defined(Debug): 
    result.repr.echo

id_pkts cs, 
  cs_login, cs_pubchat, cs_sync_component
id_pkts sc,
  sc_serverinfo, sc_loginresponse, sc_notification,
  sc_shutdown, sc_sync_component, 
  sc_client_list, sc_client_quit, 
  sc_pubchat

const
  pc_game* = 0.cuchar
  pc_room* = 1.cuchar
  pc_serv* = 2.cuchar
  pc_misc* = 3.cuchar
const
  packet_channels* = pc_misc.csize

proc wrap_shl* (ty: PNimrodNode; fields: varargs[PNimrodNode]): PNimrodNode {.compiletime.} =
  let exported_name = newNimNode(nnkAccQuoted).add(ident"<<").postfix("*")  
  result = newProc(
    name = exported_name,
    params = [
      newEmptyNode(),
      newIdentDefs(ident"L", newNimNode(nnkVarTy).add(ident"OPkt")),
      newIdentDefs(ident"R", ty.copyNimTree)
    ]
  )
  var body = newStmtList()
  for f in fields:
    body.add ident("L").infix("<<", f.copyNimTree)
  result.body = body
  
  when defined(debug):
    result.repr.echo
    

proc `[]`* (node:PNimrodNode; slice: TSlice[int]): seq[PNimrodNode] {.compiletime.}=
  result = @[]
  let high = if slice.b < 0: node.len + slice.b else: slice.b
  for i in slice.a .. high:
    result.add node[i].copyNimTree 

macro simplewrap (args:varargs[expr]):stmt{.immediate.}=
  ## this_ty = args[0]
  ## fields = args[1..-1]
  ## 
  ##
  ## proc << (L: var OPkt; R: this_ty) =
  ##   mixin <<
  ##   L << this_ty_id
  ##   L << fields[0]
  ##   L << fields[1]
  ## 
  ## proc >> (L: PPacket; R: var this_ty) =
  ##   mixin >>
  ##   L >> fields[0]
  ##   L >> fields[1]
  ##
  let cs = callsite()
  
  result = newStmtList()
  
  let 
    ty = cs[1]
    args = cs[1 .. -1]
  
  let p1 = newProc(
    name = newNimNode(nnkAccQuoted).add(ident"<<").postfix("*"),
    params = [
      newEmptyNode(), 
      newIdentDefs(ident"L", newNimNode(nnkVarTy).add(ident"OPkt")),
      newIdentDefs(ident"R", ty)
    ]
  )
  let p2 = newProc(
    name = newNimNode(nnkAccQuoted).add(ident">>").postfix("*"),
    params = [
      newEmptyNode(),
      newIdentDefs(ident"L", ident"PPacket"),
      newIdentDefs(ident"R", newNimNode(nnkVarTy).add(ty))
    ]
  )
  block:
    var body_1 = newStmtList(
      ident("L").infix("<<", ident($ty & "_id"))
    )
    var body_2 = newStmtList(  )
    for idx in 2 .. < len(cs):
      let f = cs[idx]
      body1.add(
        ident("L").infix("<<", f.copyNimTree)
      ) 
      body2.add(
        ident("L").infix(">>", f.copyNimTree)
      )
  
    p1.body = body_1
    p2.body = body_2
  
  result.add p1,p2
  
  result.repr.echo
  
  var f = wrap_shl(ty, args)

  
simplewrap cs_pubchat, r.msg 
simplewrap sc_pubchat, r.author,r.msg
simplewrap sc_notification, r.msg
simplewrap cs_login, r.user,r.pass


simplewrap sc_client_quit, r.client
proc `<<`* (L:var Opkt; R:TClientListItem) =
  L << R.id
  L << R.name
proc `>>`* (L:PPacket; R:var TClientListItem)=
  L >> R.id
  L >> R.name
simplewrap sc_client_list, r.clients

simplewrap sc_serverinfo, r.version[0],r.version[1],r.version[2]

simplewrap cs_sync_component, r.entity,r.component,r.data
proc `>>`* (L:PPacket;R:var scSyncComponent) =
  L>>r.pkt.entity
  L>>r.pkt.component
  L>>r.pkt.data
proc `<<`* (L:var OPkt; R: scSyncComponent) =
  L<<sc_sync_component_id
  L<<r.pkt.entity
  L<<r.pkt.component
  L<<r.pkt.data

proc `<<`* (L:var OPkt; R: scLoginResponse) =
  L << scLoginResponseID
  L << R.goodLogin
  if R.goodLogin:
    L << R.client_id
  else:
    L << R.msg

proc `>>`* (L:PPacket; R:var scLoginResponse) =
  var b:bool
  L >> b
  r.goodLogin = b
  if R.goodLogin:
    L >> r.client_id
  else:
    L >> r.msg





template echoCode* (x): stmt =
  echo astToStr(x), " #=> ", x


proc send* (Peer: PPeer; channel: cuchar; pkt: var OPkt; flags: cint = 0): cint {.discardable.}=
  let p = pkt.createPacket(flags)
  when defined(debug):
    echoCode peer.isNil
  result = peer.send(channel, p)
  #if not p.isNIL: destroy P
  
  if result != 0:
    raise newException(EEnet, "Could not send the packets =(")


proc broadcast* (H:PHost; channel: cuchar; pkt:var OPkt; flags: cint = 0) =
  let p = pkt.createPacket(flags)
  H.broadcast channel, p 
  #destroy p


import components, entoody

var sync_component_size* : seq[int]
newSeq sync_component_size, entoody.numComponents

type TSyncCompF* = proc(entity: PEntity): seq[byte] 
var sync_component_functions* : seq[TSyncCompF]
newSeq sync_component_functions, entoody.numComponents

template syc_impl (ty:expr; body:stmt): stmt =
  block:
    let id = componentID(ty)
    #sync_component_functions[id] = cast[TSyncCompF](entity

type SYBodyDat = object
  pos: array[2,float32]
  ang: float32



discard """ syc_impl(Body) do -> seq[byte]:
  var bd: SY_Body_dat
  # result is sy_body_dat """


