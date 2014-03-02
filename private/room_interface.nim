import chipmunk as cp
import 
  fowltek/idgen, fowltek/entitty, fowltek/bbtree, fowltek/boundingbox,
  fowltek/qtree2
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
    ents*: seq[TEntity]
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
      qtree*: qtree2.TQuadTree[int]
    of RPTBBtree:
      tree*: bbtree.TBBTree[int]

  PDoomSys* = ref object of TSystem
    doomed*: seq[int]
  
  TeamSystem* = ref object of TSystem
    teams*: seq[PTeam]
    teamNames*: TTable[string,int]

proc initBasicSystems*(R:PRoom)=
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

proc init* (R:PRenderSystem) =
  case r.partitiontype
  of rptBBtree:
    r.tree = newBBtree[int]()
  else:
    discard

proc get_ent* (r: PRoom; id: int): PEntity = r.ents[id]
proc `[]`* (R: PRoom; ID: int): PEntity = r.ents[id]

proc doom* (r: PRoom; ent: int)=
  if r.getEnt(ent).id == ent:
    r.doomSys.doomed.add ent

proc getTeam* (R: PRoom; id: int): TMaybe[PTeam] =
  if id in 0 .. < R.teamSys.teams.len:
    return Just(r.teamSys.teams[id])
proc getTeam* (R: PRoom; name: string): TMaybe[PTeam] =
  if R.teamSys.teamNames.hasKey(name):
    return R.getTeam( r.teamSys.teamNames[name] )

proc soundBuf* (R: PRoom): soundbuffer.PSoundBuffer {.inline.} =
  R.gameData.soundBuf