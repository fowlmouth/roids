
import 
  fowltek/entitty, fowltek/idgen, 
  private/components, private/gamedat,  
  basic2d, math,json
import csfml except pshape
import chipmunk as cp
import private/room_interface

var gamedata*: TGamedata


proc get_ent* (r: PRoom; id: int): PEntity = 
  r.ents[id]

proc add_ent* (r: PRoom; e: TEntity): int {.discardable.} =
  result = r.ent_id.get
  if r.ents.len < result+1: r.ents.setLen result+1
  r.ents[result] = e
  r.getEnt(result).id = result
  r.getEnt(result).addToSpace r.space
  r.activeEnts.add result

proc destroy_ent* (r: PRoom; id: int) =
  r.getEnt(id).removeFromSpace(r.space)
  destroy r.getEnt(id)
  r.activeEnts.del r.activeEnts.find(id)
  r.ent_id.release id

proc free* (r: PRoom) =
  echo "Freeing room! ", r.activeEnts.len, " active ents"
  for idx in r.activeEnts:
    r.getEnt(idx).removeFromSpace r.space
    destroy r.getEnt(idx)
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
    r.getEnt(id).update dt
    r.getEnt(id).execRCs r
  r.space.step dt
  proc reset_forces (b: PBody; d: pointer){.cdecl.} =
    b.resetForces
  r.space.eachBody(reset_forces, nil)

proc fireEmitter (e: PEntity) =
  if e[emitter].cooldown <= 0:
    e.scheduleRC do(x: PEntity; r: PRoom):
      # schedule an entity to be created
      var ent = gameData.newEnt(x[emitter].emits)
      ent.setPos x.getPos
      var ii = x[emitter].initialImpulse
      ii.rotate x.getAngle
      ent.impulse ii
      r.add_ent ent
      x[emitter].cooldown = x[emitter].delay

msgImpl(Emitter,update) do (dt: float):
  let e = entity[emitter].addr
  e.cooldown -= dt
  if e.mode == emitterMode.auto:
    entity.fireEmitter

msgImpl(Emitter,fire) do:
  entity.fireEmitter
