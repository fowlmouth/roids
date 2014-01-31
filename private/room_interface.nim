import chipmunk as cp
import fowltek/idgen, fowltek/entitty, private/components, fowltek/bbtree, fowltek/boundingbox
type
  PRoom* = ref object
    ents*: seq[TEntity]
    ent_id*: TIDgen[int]
    updateSYS*: PUpdateSystem
    doomSys*:PDoomSys
    physSys*: PPhysicsSystem
    renderSYS*: PRenderSystem
    
  TSystem* = object{.inheritable.}
  
  PUpdateSystem* = ref object of TSystem
    active*: seq[int]
  PPhysicsSystem* = ref object of TSystem
    space*: PSpace

  PRenderSystem* = ref object of TSystem
    tree*: bbtree.TBBTree[int]

  PDoomSys* = ref object of TSystem
    doomed*: seq[int]

proc initSystems* (r: PRoom) =
  r.updateSys = PUpdateSystem(active: @[])
  r.physSys   = PPhysicsSystem(space: newSpace())
  r.renderSys = PRenderSystem(tree: newBBtree[int]())
  r.doomsys   = PDoomSys(doomed: @[])

proc get_ent* (r: PRoom; id: int): PEntity = 
  r.ents[id]

proc doom* (r: PRoom; ent: int)=
  if r.getEnt(ent).id == ent:
    r.doomSys.doomed.add ent





