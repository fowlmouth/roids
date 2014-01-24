
import fowltek/entitty, fowltek/idgen
import components, gamedat, basic2d, math,json
import csfml except pshape
import chipmunk as cp

type
  PRoom* = ref object
    space*: PSpace
    ents: seq[TEntity]
    ent_id: TIDgen[int]
    activeEnts: seq[int]

var
  gamedata*: TGameData

proc get_ent* (r: PRoom; id: int): PEntity = 
  r.ents[id]
proc destroy_ent* (r: PRoom; id: int) =
  r.getEnt(id).removeFromSpace(r.space)
  destroy r.getEnt(id)
  r.activeEnts.del r.activeEnts.find(id)
  r.ent_id.release id

proc add_ent* (r: PRoom; e: TEntity) =
  let id = r.ent_id.get
  if r.ents.len < id+1: r.ents.setLen id+1
  r.ents[id] = e
  r.ents[id].id = id
  r.ents[id].addToSpace r.space
  r.activeEnts.add id

proc add_asteroid* (r: PRoom; p: TPoint2d) =
  var ent = newEnt(gamedata, gamedata.randomFromGroup("asteroids"))
  ent.setPos p
  let force = polarVector2d(random(360)/360*DEG360, random(50 .. 100).float)
  ent.impulse force
  ent[body].s.setElasticity(1.0)
  r.add_ent ent

proc free* (r: PRoom) =
  for idx in r.activeEnts:
    destroy r.ents[idx]
    r.ents[idx].id = -1
  destroy r.space
  free r.space

proc room* (space: PSpace): PRoom = 
  cast[PRoom](space.getUserdata)
proc entID* (shape: cp.PShape): int = 
  cast[int](shape.getUserdata)

proc call_collision_cb (arb: PArbiter; space: PSpace; data: pointer){.cdecl.}=
  let 
    e1 = arb.a.entID
    e2 = arb.b.entID
  if e1 == 0 or e2 == 0: return
  space.room.getEnt(e1).handleCollision(space.room.getEnt(e2))
  space.room.getEnt(e2).handleCollision(space.room.getEnt(e1))
  
proc handle_gravity (arb: PArbiter; space: PSpace; data: pointer): bool {.cdecl.} =
  var shape_a, shape_b : cp.PShape
  arb.getShapes shape_a,shape_b
  # the gravity sensor is shape_a
  let
    grav_id = shape_a.entID
  template ent_a: expr = space.room.getEnt(grav_id)
  
  let
    delta = shape_a.getBody.getPos - shape_b.getBody.getPos
    force = ent_a[GravitySensor].force / delta.lenSq
  
  shape_b.getBody.applyImpulse(#applyForce(
    delta.normalize * force,
    vectorZero)

proc newRoom* (j: PJsonNode) : Proom =
  result.new free
  result.activeEnts = @[]
  result.ents = @[]
  result.ent_id = newIDgen[int]()
  discard result.ent_id.get # use up 0
  result.space = newSpace()
  result.space.setUserdata(cast[pointer](result))
  
  result.space.addCollisionHandler(
    ct"gravity", 0.cuint, 
    presolve = handleGravity
  )
  result.space.addCollisionHandler(
    0, 0,
    postSolve = callCollisionCB
  )
  
  # bounds
  let bounds = j["bounds"]
  for i in 0 .. < bounds.len:
    
    let b = result.space.getStaticBody
    let v1 = vector(bounds[i][0].toFloat, bounds[i][1].toFloat)
    template ii: expr = (i + 1) mod 4
    let v2 = vector(bounds[ii][0].toFloat, bounds[ii][1].toFloat)
    var s = newSegmentShape(b, v1, v2, 1.0)
    s.setElasticity 0.5
    discard result.space.addshape( s)

  for obj in j["objects"]:
    var 
      count: int
    count.getInt obj, "count", 1
    
    if obj.hasKey("obj"):
      var ent = gameData.newEnt(obj["obj"].str)
      if obj.hasKey("extra-data"):
        ent.unserialize obj["extra-data"]
      result.addEnt ent
      continue
    
    if obj.hasKey("group"):
      let g = obj["group"].str
      for i in 0 .. < count:
        var ent = gameData.newEnt(gameData.randomFromGroup(g))
        if obj.hasKey("extra-data"):
          ent.unserialize obj["extra-data"]
        result.addEnt ent


proc update* (r: PRoom; dt: float) =
  for id in r.activeEnts:
    r.ents[id].update dt
  r.space.step dt
  proc reset_forces (b: PBody; d: pointer){.cdecl.} =
    b.resetForces()
  r.space.eachBody(reset_forces, nil)
