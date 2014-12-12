import chipmunk as cp except TBB,TBBTree
import 
  fowltek/idgen, entoody, fowltek/bbtree, fowltek/boundingbox,
  fowltek/qtree
import 
  private/components, private/emitter_type,
  private/soundbuffer,
  json

type

  PGameData* = ref TGameData
  TGameData* = object
    entities*: TTable[string,TJent] # ent name => typeinfo and json data
    groups*: TTable[string, seq[string]] # group name => @[ ent names ]
    rooms*: TTable[string, PJsonNode]
    emitters*: TTable[string,PEmitterType]
    sounds*: TTable[string,PSoundCached]
    soundBuf*: PSoundBuffer
    dir*: string
    firstRoom*:string
    j*: PJsonNode 
  TJent* = tuple
    ty: PTypeinfo
    j1, j2: PJsonNode

  PTeam* = ref object
    id*: int
    name*: string
    members*: seq[int]

  PRoom* = ref object
    ents*: seq[PEntity]
    ent_id*: TIDgen[int]
    updateSYS*: PUpdateSystem
    doomSys*:PDoomSys
    physSys*: PPhysicsSystem
    renderSYS*: PRenderSystem
    teamSYS* : TeamSystem
    name*: string
    bounds*: TMaybe[seq[PShape]]
    gameData*: PGameData
    w*,h*: int
    
  TSystem* = object{.inheritable.}
  
  PUpdateSystem* = ref object of TSystem
    active*: seq[int]
  PPhysicsSystem* = ref object of TSystem
    space*: PSpace

  RoomPartitionType* = enum
    RPTQuadTree, RPTBBTree

  PRenderSystem* = ref object of TSystem
    parallaxEntities*: seq[int]
    case partitionType*: RoomPartitionType
    of RPTQuadTree:
      qtree*: qtree.TQuadTree[int]
    of RPTBBtree:
      tree*: bbtree.TBBTree[int]

  PDoomSys* = ref object of TSystem
    doomed*: seq[int]
  
  TeamSystem* = ref object of TSystem
    teams*: seq[PTeam]
    teamNames*: TTable[string,int]

proc initBasicSystems*(r:PRoom)=
  r.updateSys = PUpdateSystem(active: @[])
  r.doomSys = PDoomSys(doomed: @[])
  r.physSys = PPhysicsSystem(space: newSpace())
  r.teamsys = TeamSystem(
    teams: @[], teamNames: initTable[string,int](64)
  )
proc initSystems* (r: PRoom) =
  r.initBasicSystems
  r.renderSys = PRenderSystem(
    parallaxEntities: @[]
  )

proc init* (r:PRenderSystem) =
  case r.partitiontype
  of RPTBBtree:
    let tree: TBBTree[int] = bbtree.newBBtree[int]()
  else:
    discard

proc get_ent* (r: PRoom; id: int): PEntity = r.ents[id]
proc `[]`* (r: PRoom; id: int): PEntity = r.ents[id]

proc doom* (r: PRoom; ent: int)=
  if r.getEnt(ent).id == ent:
    r.doomSys.doomed.add ent

proc getTeam* (r: PRoom; id: int): TMaybe[PTeam] =
  if id in 0 .. < r.teamSys.teams.len:
    return Just(r.teamSys.teams[id])
proc getTeam* (r: PRoom; name: string): TMaybe[PTeam] =
  if r.teamSys.teamNames.hasKey(name):
    return r.getTeam( r.teamSys.teamNames[name] )

proc soundBuf* (r: PRoom): soundbuffer.PSoundBuffer {.inline.} =
  r.gameData.soundBuf