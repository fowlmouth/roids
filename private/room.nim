
import 
  fowltek/entitty, fowltek/idgen, fowltek/bbtree,fowltek/boundingbox, 
  private/components, private/gamedat,  private/room_interface,
  basic2d, math,json, algorithm
import csfml except pshape
import chipmunk as cp

var gamedata*: TGamedata


proc add* (S:PUpdateSystem; ent: int) =
  S.active.add ent
proc add* (S:PRenderSystem; ent:int; r:PRoom)=
  S.tree.insert ent, r.getEnt(ent).getBB
proc add* (S:PPhysicsSystem; ent:int; r:PRoom)=
  r.getEnt(ent).addToSpace (s.space)

proc add_to_systems* (entity: int; r: PRoom) =
  r.updateSYS.add entity
  r.renderSYS.add entity, r
  r.physSys.add entity, r

proc rem_from_systems* (ent:int;r:PRoom)=
  r.updateSys.active.del r.updateSys.active.find(ent)
  r.renderSys.tree.remove ent
  r.getEnt(ent).removeFromSpace(r.physSys.space)

proc add_ent* (r: PRoom; e: TEntity): int {.discardable.} =
  result = r.ent_id.get
  if r.ents.len < result+1: r.ents.setLen result+1
  r.ents[result] = e
  r.getEnt(result).id = result
  # add entity to updatesys, rendersys, physicssys etc
  add_to_systems result, r

proc destroy_ent (r: PRoom; id: int) =
  echo "destroyed entity #",id, ": ", r.getEnt(id).getName
  id.rem_from_systems(r)
  destroy r.getEnt(id)
  r.ent_id.release id

proc run* (s: PDoomSys; r: PRoom)= 
  for id in s.doomed:
    r.destroyEnt(id)
  s.doomed.setLen 0


proc free* (r: PRoom) =
  #echo "Freeing room! ", r.activeEnts.len, " active ents"
  while r.updateSys.active.len > 0:
    let id = r.updateSys.active[0]
    r.destroyEnt id
  #free r.space

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
  #  force = ent_a[GravitySensor].force / delta.lenSq
  let force = ent_a[GravitySensor].force * 1 / delta.lenSq
  shape_b.getBody.applyImpulse(
    delta.normalizeSafe * force,
    vectorZero)

proc newRoom* (j: PJsonNode) : Proom =
  result.new free
  
  result.initSystems
  
  result.ents = @[]
  result.ent_id = newIDgen[int]()
  discard result.ent_id.get # use up 0
  
  template space: expr = result.physSys.space
  space.setUserdata(cast[pointer](result))
  
  space.addCollisionHandler(
    ct"gravity", 0.cuint, 
    presolve = handleGravity
  )
  space.addCollisionHandler(
    0, 0,
    postSolve = callCollisionCB
  )
  
  # bounds
  if j.hasKey"bounds":
    var bounds: seq[TVector] = @[]
    if j["bounds"].kind == jObject:
      let w = j["bounds"]["width"].toFloat
      let h = j["bounds"]["height"].toFloat
      bounds.add vector(0,0)
      bounds.add vector(w,0)
      bounds.add vector(w,h)
      bounds.add vector(0,h)
    else:
      for b in j["bounds"]:
        bounds.add vector(vector2d(b))
    
    for i in 0 .. < bounds.len:
      let
        b = space.getStaticBody
        v1 = bounds[i]
        v2 = bounds[(i+1) mod bounds.len]
        s = newSegmentShape(b, v1, v2, 1.0)
      s.setElasticity 0.5
      discard space.addShape(s)

  for obj in j["objects"]:
    var 
      count: int
    count.getInt obj, "count", 1
    
    for i in 0 .. <count:
      var ent: TEntity
      if obj.hasKey"obj":
        ent = gameData.newEnt(obj["obj"].str)
      elif obj.hasKey"group":
        ent = gameData.newEnt(gameData.randomFromGroup(obj["group"].str))
      else:
        break
      
      if obj.haskey("data"):
        ent.unserialize obj["data"]
      if obj.hasKey("extra-data"):
        ent.unserialize obj["extra-data"]
      result.addEnt ent


proc run* (s: PUpdateSystem; r:PRoom; dt: float) =
  for id in s.active:
    r.getEnt(id).update dt
    r.getEnt(id).execRCs r
proc execRCs* (s: PUpdateSystem;r:Proom) =
  for id in s.active:
    r.getEnt(id).execRCs r

proc step* (s: PPhysicsSystem; dt: float)=
  s.space.step dt
  proc reset_forces (b: PBody; d: pointer){.cdecl.} =
    b.resetForces
  s.space.eachBody(reset_forces, nil)

proc draw* (r: PRoom; bb: boundingbox.TBB; w: PRenderWindow) {.inline.} =
  for id in r.updateSys.active:
    r.renderSys.tree.update id, r.getEnt(id).getBB
  
  type TZorderEnt = tuple[ent, z: int]
  var z_ents {.global.} = newSeq[TZorderEnt](0)
  r.renderSys.tree.query(bb) do (item: int):
    #r.getEnt(item).draw(w)
    z_ents.add((item, r.getEnt(item).getZorder))
  z_ents.sort do (x, y: TZorderEnt)-> int : cmp(x.z, y.z)
  
  for ent, blah in items(z_ents):
    r.getEnt(ent).draw w
  z_ents.setLen 0

proc update* (r: PRoom; dt:float) =
  r.updateSys.run(r, dt)
  r.physSys.step(dt)
  r.updateSys.execRCs r
  r.doomsys.run(r)

proc fireEmitter (e: PEntity) =
  if e[emitter].cooldown <= 0:
    e.scheduleRC do(x: PEntity; r: PRoom):
      # schedule an entity to be created
      var ent = gameData.newEnt(x[emitter].emits)
      let angle = x.getAngle
      ent.setPos x.getPos
      ent.impulse x.getVel * x[emitter].inheritVelocity
      
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


msgImpl(CollisionHandler, unserialize) do (J: PJsonNode):
  if j.hasKey("CollisionHandler") and j["CollisionHandler"].kind == jObject:
    let j = j["CollisionHandler"]
    case j["action"].str
    of "warp":
      let p = point2d(j["position"])
      entity[collisionHandler].f = proc(self,other: PEntity) =
        other.setPos p
        other.scheduleRC do (x: PEntity; r: PRoom):
          var ent = gameData.newEnt("warp-in")
          ent.setPos x.getPos
          r.add_ent ent
    of "destroy":
      entity[CollisionHandler].f = proc(self,other: PEntity) =
        other.scheduleRC do (x: PEntity; r: PRoom):
          r.doom(x.id)

