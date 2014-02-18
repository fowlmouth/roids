import chipmunk as cp
import fowltek/idgen, fowltek/entitty, fowltek/bbtree, fowltek/boundingbox
import 
  private/components, private/emitter_type,
  json

type

  PGameData* = ref TGameData
  TGameData* = object
    entities*: TTable[string,TJent] # ent name => typeinfo and json data
    groups*: TTable[string, seq[string]] # group name => @[ ent names ]
    rooms*: TTable[string, PJsonNode]
    emitters*: TTable[string,PEmitterType]
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
    
  TSystem* = object{.inheritable.}
  
  PUpdateSystem* = ref object of TSystem
    active*: seq[int]
  PPhysicsSystem* = ref object of TSystem
    space*: PSpace

  PRenderSystem* = ref object of TSystem
    tree*: bbtree.TBBTree[int]
    parallaxEntities*: seq[int]

  PDoomSys* = ref object of TSystem
    doomed*: seq[int]
  
  TeamSystem* = ref object of TSystem
    teams*: seq[PTeam]
    teamNames*: TTable[string,int]

proc initSystems* (r: PRoom) =
  r.updateSys = PUpdateSystem(active: @[])
  r.physSys   = PPhysicsSystem(space: newSpace())
  r.renderSys = PRenderSystem(
    tree: newBBtree[int](),
    parallaxEntities: @[]
  )
  r.doomsys   = PDoomSys(doomed: @[])
  r.teamsys = TeamSystem(
    teams: @[], teamNames: initTable[string,int](64)
  )

proc get_ent* (r: PRoom; id: int): PEntity = 
  r.ents[id]

proc doom* (r: PRoom; ent: int)=
  if r.getEnt(ent).id == ent:
    r.doomSys.doomed.add ent

proc getTeam* (R: PRoom; name: string): TMaybe[PTeam] =
  if R.teamSys.teamNames.hasKey(name):
    return Just(r.teamSys.teams[r.teamSys.teamNames[name]])
proc getTeam* (R: PRoom; id: int): TMaybe[PTeam] =
  if id in 0 .. < R.teamSys.teams.len:
    return Just(r.teamSys.teams[id])

