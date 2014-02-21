
import 
  fowltek/entitty, fowltek/idgen, fowltek/bbtree,fowltek/boundingbox, 
  private/components, private/gamedat,  private/room_interface, private/debug_draw,
  private/common, private/soundbuffer,
  basic2d, math,json, algorithm, logging
import csfml except pshape
import chipmunk as cp except TBB

var gamedata*: PGameData

proc add* (S:PRenderSystem; ent:int; r:PRoom)=
  if r.getEnt(ent).hasComponent(Parallax):
    S.parallaxEntities.add ent
  else:
    S.tree.insert ent, r.getEnt(ent).getBB

proc add* (S:PUpdateSystem; ent: int) =
  S.active.add ent
proc add* (S:PPhysicsSystem; ent:int; r:PRoom)=
  r.getEnt(ent).addToSpace (s.space)

proc add_to_systems* (entity: int; r: PRoom) =
  r.updateSYS.add entity
  r.renderSYS.add entity, r
  r.physSys.add entity, r

proc remove* (S: PRenderSystem; entity: PEntity) =
  if entity.hasComponent(Parallax):
    let index = S.parallaxEntities.find(entity.id)
    if index != -1:
      S.parallaxEntities.del index
    return
  S.tree.remove entity.id

proc rem_from_systems* (ent:int;r:PRoom)=
  r.updateSys.active.del r.updateSys.active.find(ent)
  r.renderSys.remove r.getEnt(ent)
  r.getEnt(ent).removeFromSpace(r.physSys.space)

proc add_ent* (r: PRoom; e: TEntity): int {.discardable.} =
  result = r.ent_id.get
  if r.ents.len < result+1: r.ents.setLen result+1
  r.ents[result] = e
  r.getEnt(result).id = result
  # add entity to updatesys, rendersys, physicssys etc
  add_to_systems result, r

proc destroy_ent (r: PRoom; id: int) =
  debug "Destroying entity #$#: $#", id, r.getEnt(id).getName
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

proc handle_grav2 ( arb: PArbiter; space: PSpace; data:pointer): bool {.cdecl.}=
  var gravSensor,shapeB: cp.PShape
  arb.getShapes gravSensor,shapeB
  
  template gravEnt: expr = space.room.getEnt(gravSensor.entID)
  
  let
    p = shapeB.getBody.getPos - gravSensor.getBody.getPos
    sqdist = p.lenSq
    f = p * - gravEnt[gravitySensor].force / (sqdist * sqrt(sqdist))
  
  shapeB.getBody.applyImpulse(f, vectorZero)

proc set_team (R: PRoom; ent: int; team: int) =
  if(var (has,T) = R.getTeam(team); has):
    debug("Player $# joined team $#", r.getEnt(ent).getName, T.name)
    R.getEnt(ent)[TeamMember].team = team
    T.members.add ent

proc `$` * (s: seq[int]): string =
  result = "["
  for i in 0 .. < len(s):
    result.add ($ s[i])
    if i < high(s):
      result.add ", "
  result.add ']'
proc `$` * (t:PTeam): string = 
  if t.isNil: "nil.PTeam"
  else: $ (t[])

proc add_team (R: PRoom; name: string): int {.discardable.}=
  result = r.teamSys.teams.len
  r.teamSys.teams.ensureLen result+1
  r.teamSys.teams[result] = PTeam(
    id: result, 
    name: name, 
    members: @[]
  )
  r.teamSys.teamNames[name] = result
  
  debug "New team $#", r.teamSys.teams[result]
  
proc initRoom (room: PRoom; j: PJsonNode) =
  room.name = j["name"].str
  room.ents = @[]
  room.ent_id = newIDgen[int]()
  room.gameData = gameData
  discard room.ent_id.get # use up 0
  
  block:
    template space: expr = room.physSys.space
    space.setUserdata(cast[pointer](room))
    
    space.addCollisionHandler(
      ct"gravity", 0.cuint, 
      presolve = handleGrav2
    )
    space.addCollisionHandler(
      0, 0,
      postSolve = callCollisionCB
    )
    
    # bounds
    if j.hasKey"bounds":
      var bounds: seq[TVector] = @[]
      if j["bounds"].kind == jObject:
        if j["bounds"].hasKey("shape"):
          if j["bounds"]["shape"].str == "circle":
            let radius = j["bounds"]["radius"].toFloat
            let center = vector2d(radius, radius)
            let points = if j["bounds"].hasKey("points"): j["bounds"]["points"].toInt else: 30
            for i in 0 .. < points:
              bounds.add polarVector2d(deg360 * (i / points), radius) + center
        else:
          let w = j["bounds"]["width"].toFloat
          let h = j["bounds"]["height"].toFloat
          bounds.add vector(0,0)
          bounds.add vector(w,0)
          bounds.add vector(w,h)
          bounds.add vector(0,h)
      elif j["bounds"].kind == jArray:
        for b in j["bounds"]:
          bounds.add vector(vector2d(b))
      
      room.bounds = just(newseq[cp.pshape](0))
      for i in 0 .. < bounds.len:
        const borderRadius = 10.0
        let
          b = space.getStaticBody
          v1 = bounds[i]
          v2 = bounds[(i+1) mod bounds.len]
          s = newSegmentShape(b, v1, v2, borderRadius)
        s.setElasticity 0.5
        room.bounds.val.add( space.addShape(s) )
  
  proc import_team (team_id: int; j: PJsonNode) =
    var entities: PJsonNode
    if j.kind == jArray:
      # list of entities
      entities = j
    elif j.kind == jObject:
      entities = j["entities"]
    else:
      return
    
    for entity in entities:
      let
        entity_type = entity[0]
        entity_data = entity[1]

      var ent: TEntity
      ent = gameData.newEnt(room, entity_type)
      dom.addComponents(ent, TeamMember)
      ent.unserialize entity[1], room
      
      let ent_id = room.addEnt(ent)
      room.setTeam ent_id, team_id

  
  add_team room, "Spectators"
  if j.hasKey"teams":
    for name, team in j["teams"]:
      let team_id = add_team(room, name)
      import_team team_id, team

  proc importObject (n: PJsonNode) =
    var 
      count = 1
      objTy: PJsonNode
      data: PJsonNode
    if n.kind == jArray:
      objTy = n[0]
      if n.len == 3:
        count = n[1].toInt
        data = n[2]
      elif n.len == 2:
        data = n[1]
    elif n.kind == jObject:
      if n.hasKey("group"):
        objTy = %[%"group", n["group"]]
      elif n.hasKey("obj"):
        objTy = n["obj"]
      
      if n.hasKey("data"):
        data = n["data"]
      elif n.hasKey("extra-data"):
        data = n["extra-data"]
    else:
      return
    
    for i in 0 .. < count:
      var ent: TEntity
      try:
        ent = gameData.newEnt(room,objTy)
      except EInvalidKey:
        warn "Entity not found $#", objTy
        break

      ent.unserialize data, room
      room.addEnt(ent)

  if j.hasKey("objects"):
    let j = j["objects"]
    for obj in j:
      importObject(obj)
  else:
    warn "No objects in this room."
    

proc newRoom* (j: PJsonNode) : Proom =
  result.new free
  info "Creating a new room."
  result.initSystems
  result.initRoom j

proc remove* [T] (s: var seq[T]; item: T) =
  if (let index = s.find(item); index != -1):
    s.delete index

proc setPlayerteam (R:PRoom;player,team:int) =
  if team != R.getEnt(player)[TeamMember].team:
    R.getTeam(R.getEnt(player)[TeamMember].team).val.members.remove(player)
  R.setTeam(player, team)

proc getPlayerTeam* (R: PRoom; player: int): TMaybe[PTeam] =
  if R.getEnt(player).hasComponent(TeamMember):
    result = R.getTeam(R.getEnt(player)[TeamMember].team)

proc joinPlayer* (R: PRoom; name: string): int =
  var ent = dom.newEntity(Named, Owned, TeamMember, Radar)
  ent[Named].s = name
  ent[Radar].r = 1200.0
  result = R.addEnt(ent)
  R.setPlayerTeam result, 0
  
  debug "Player $# joined room $# (team $#)",
    r.getEnt(result).getName, r.name,
    R.getTeam(R.getEnt(result)[TeamMember].team)

proc findRole* (T: PTeam; R: PRoom; role: string): seq[int] =
  result = @[]
  for member in T.members:
    if R.getEnt(member).hasRole(role):
      result.add member
proc firstMaybe* [T] (s: seq[T]): TMaybe[T] =
  if s.isNil or s.len == 0:
    return
  return just(s[0])

proc requestUnspec* (R: PRoom; player: int; veh: string): TMaybe[int] =
  # puts the player on a team and give them a vehicle
  
  # find a team if player team is 0
  var playerTeam = r.getPlayerTeam(player)
  if r.teamSys.teams.len > 1 and not(playerTeam.has) or playerTeam.val.id == 0:
    # put them on a team
    r.setPlayerTeam player, 1
    playerTeam = r.getPlayerTeam(player)

  # vehicle
  var ent = gameData.newEnt(R,veh)
  dom.addComponents ent, Owned
  ent[Owned].by = player
  let vehicle_id = R.addEnt(ent)
  result = Just(vehicle_id)

  let spawnPoint = playerTeam.val.findRole(r, "spawn-point").firstMaybe
  if spawnPoint:
    let pos = r.getEnt(spawnPoint.val).getPos
    R.getEnt(vehicle_id).setPos pos
  else:
    debug "Spawnpoint not found for team $#", playerTeam


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

template once* (body:stmt): stmt =
  var hasRan {.global.} = false
  if not hasRan:
    body
    hasRan = true

proc draw_parallax (r: PRoom; w: PRenderWindow) {.inline.} =
  # draw parallax background layer
  if r.renderSys.parallaxEntities.len == 0: return
  
  let center = w.getView.getCenter
  let oldView = w.getView
  let view = oldView.copy
  w.setView view
  for p_ent in r.renderSys.parallaxEntities:
    view.setCenter center * r.getEnt(p_ent)[Parallax].offs
    r.getEnt(p_ent).draw w
  w.setView oldView
  destroy view
proc draw* (r: PRoom; bb: boundingbox.TBB; w: PRenderWindow) {.inline.} =
  r.renderSys.tree.update do (item: int) -> TBB: r.getEnt(item).getBB
  
  r.draw_parallax w
  
  if r.bounds.has:
    for s in r.bounds.val: debugDrawShape(s, w)
  
  type TZorderEnt = tuple[ent, z: int]
  var z_ents {.global.} = newSeq[TZorderEnt](0)
  r.renderSys.tree.query(bb) do (item: int):
    #r.getEnt(item).draw(w)
    z_ents.add((ent: item, z: r.getEnt(item).getZorder))
  z_ents.sort do (x, y: TZorderEnt)-> int : cmp(x.z, y.z)
  
  for ent, blah in items(z_ents):
    r.getEnt(ent).draw w
  z_ents.setLen 0

proc update* (r: PRoom; dt:float) =
  r.updateSys.run(r, dt)
  r.physSys.step(dt)
  r.updateSys.execRCs r
  r.doomsys.run(r)

proc countAliveKind* (R:PRoom; kind:PJsonNode): int =
  proc contains (J:PJsonNode; str:string): bool =
    if j.kind == jArray and j[0].kind == jString and j[0].str == "group":
      if gamedata.groups.hasKey(j[1].str):
        result = str in gamedata.groups[j[1].str]
        return
    result = (j.kind == jString and j.str == str)
  
  for ent in R.updateSys.active:
    if R.getEnt(ent).get_name in kind:
      inc result

proc evalFloat* (J:PJsonNode; R: PRoom): float = 
  if j.kind == jArray:
    case j[0].str
    of "entities-alive":
      result = R.countAliveKind(j[1]).float
      return
  result = j.toFloat

proc evalBool* (J:PJsonNode; R: PRoom): bool =
  if j.kind == jArray:
    case j[0].str
    of "<":
      result = j[1].evalFloat(R) < j[2].evalFloat(R)
    of ">":
      result = j[1].evalFloat(R) > j[2].evalFloat(R)
    of "and":
      result = j[1].evalBool(R)
      if result: result = j[2].evalBool(R)
    of "or":
      result = j[1].evalBool(R)
      if not result: result = j[2].evalBool(R)
    of "not":
      result = not j[1].evalBool(R)



msgImpl(CollisionHandler, unserialize) do (J: PJsonNode; R: PRoom):
  if j.hasKey("CollisionHandler") and j["CollisionHandler"].kind == jObject:
    let j = j["CollisionHandler"]
    case j["action"].str
    of "warp":
      let p = point2d(j["position"])
      entity[collisionHandler].f = proc(self,other: PEntity) =
        other.setPos p
        other.scheduleRC do (x: PEntity; r: PRoom):
          var ent = gameData.newEnt(r, "warp-in")
          ent.setPos x.getPos
          r.add_ent ent
    of "destroy":
      entity[CollisionHandler].f = proc(self,other: PEntity) =
        other.scheduleRC do (x: PEntity; r: PRoom):
          r.doom(x.id)



import private/emitter_type

proc canFire (x: PEntity; e: PEmitterType; room: PRoom): bool =
  if e.isNil: return false
  
  if e.energyCost.has and e.energyCost.val > x.getEnergy:
    return false
  
  if e.logic.has:
    return evalBool(e.logic.val, room)
  
  return true

proc canFire* (emitter: Emitter): bool{.inline.} =
  emitter.cooldown <= 0
proc canFire* (x: PEntity; emitter: var Emitter; room: PRoom): bool {.inline.}=
  x.canFire(emitter.e, room) and emitter.canFire

proc playSound* (R: PRoom; sound: PSoundCached; pos: TPoint2d) {.inline.} =
  R.soundBuf.playSound sound , pos

proc fireET (R: PRoom; parent: int; ET: PEmitterType) =
  template x: expr = r.getEnt(parent)
  
  case et.kind.k
  of emitterKind.single:
    var ent = gameData.newEnt(r, et.emitsJson)
    if ent.data.isNil:
      return
      
    let 
      angle = x.getAngle + et.angle
    ent.setPos x.getPos 
    ent.setVel (( x.getVel * et.inheritVelocity ) + angle.polarVector2d(et.muzzleVelocity))
    
    var ii = x[emitter].e.initialImpulse
    ii.rotate x.getAngle
    ent.impulse ii
    r.add_ent ent
  of emitterkind.multi:
    for et in et.kind.multi:
      fireET r, parent, et
  
  if et.fireSound:
    r.playSound et.fireSound.val, r.getEnt(parent).getPos

proc fireEmitter (e: PEntity) =
  if e[emitter].canFire: 
    e.scheduleRC do(x: PEntity; r: PRoom):
      # schedule an entity to be created
      if not(x.canFire(x[emitter], r)) or not(x.secureEnergy(x[emitter].e.energyCost)):
        return
      
      
      let id = x.id
      fireET r, id, x[emitter].e
      # creating new entities might cause reallocations
      r.getEnt(id)[emitter].cooldown = r.getEnt(id)[emitter].e.delay

proc fireEmitterSlot(entity: PEntity; slot: int) =
  if entity[emitters].ems[slot].canFire:
    let slot = slot
    
    entity.scheduleRC do (X: PEntity; R: PRoom):
      let id = x.id
      template this_em : expr = r.getEnt(id)[emitters].ems[slot]
      if not x.canFire(this_em, r) or not(x.secureEnergy(this_em.e.energyCost)):
        return
      fireET r, id, this_em.e
      this_em.cooldown = this_em.e.delay


msgImpl(Emitter,update) do (dt: float):
  let e = entity[emitter].addr
  e.cooldown -= dt
  if e.mode == emitterMode.auto:
    entity.fireEmitter
msgImpl(Emitters,update) do (dt: float):
  for i in 0 .. < entity[emitters].ems.len:
    template this_em : expr = entity[emitters].ems[i]
    this_em.cooldown -= dt
    if this_em.mode == emitterMode.auto:
      entity.fireEmitterSlot i


msgImpl(Emitter,fire, 100) do (slot: int):
  if entity[emitter].canFire:
    entity.fireEmitter 

msgImpl(Emitters, fire, 101) do (slot: int):
  if slot in 0 .. < entity[emitters].ems.len:
    entity.fireEmitterSlot slot


