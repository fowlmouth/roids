
import 
  entoody, fowltek/idgen, fowltek/bbtree,fowltek/boundingbox, 
  private/components, private/gamedat,  private/room_interface, private/debug_draw,
  private/common, private/soundbuffer, fowltek/qtree,
  basic2d, math,json, algorithm
import csfml except pshape
import chipmunk as cp except TBB


proc newEnt* (R: PRoom; name: string): PEntity =
  when defined(debug):
    echo "Instantiating entity $#" % name
  let tj = r.gameData.entities.mget(name).addr
  result = tj.ty.newEntity
  result.unserialize tj.j1, r
  result.unserialize tj.j2, r

proc newEnt* (R: PRoom; name: PJsonNode): PEntity =
  if name.kind == jArray and name[0].kind == jString and name[0].str == "group":
    return newEnt(r, R.gameData.random_from_group(name[1].str))
  elif name.kind == jString:
    return newEnt(r, name.str)

proc add* (S:PRenderSystem; ent:int; r:PRoom)=
  if r.getEnt(ent).hasComponent(Parallax):
    S.parallaxEntities.add ent
  else:
    if s.partitiontype == rptBBtree:
      S.tree.insert ent, r.getEnt(ent).getBB
    elif s.partitiontype == rptQuadTree:
      s.qtree.insert r.getEnt(ent).getBB, ent

proc add* (S:PUpdateSystem; ent: int) =
  S.active.add ent
proc add* (S:PPhysicsSystem; ent:int; r:PRoom)=
  r.getEnt(ent).addToSpace (s.space)

proc add_to_systems* (entity: int; r: PRoom) =
  r.updateSYS.add entity
  if not r.renderSys.isNil: r.renderSYS.add entity, r
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

proc add_ent* (r: PRoom; e: PEntity): int {.discardable.} =
  result = r.ent_id.get
  if r.ents.len < result+1: r.ents.setLen result+1
  r.ents[result] = e
  r.getEnt(result).id = result
  # add entity to updatesys, rendersys, physicssys etc
  add_to_systems result, r
  r.getEnt(result).addToRoom r

proc destroy_ent (r: PRoom; id: int) =
  if r.getEnt(id).id == -1: return
  debugEcho "Destroying entity #$#: $#".format( id, r.getEnt(id).getName )
  id.rem_from_systems(r)
  destroy r.getEnt(id)
  r.getEnt(id).id = -1
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

proc presolve_collision_cb (arb:PArbiter; space:PSpace; data:pointer): bool{.cdecl.}=
  # return false to ignore collision, true to do it
  result = true
  let
    e1 = arb.a.entID
    e2 = arb.b.entID
  if e1 < 1 or e2 < 1:
    return true
  if space.room.getEnt(e1).getOwner == e2 or space.room.getEnt(e2).getOwner == e1:
    return false
  if (var (has,t1) = space.room[e1].getTeam; has):
    if (var (has,t2) = space.room[e2].getTeam; has and t1 == t2):
      return false
  
proc postsolve_collision_cb (arb: PArbiter; space: PSpace; data: pointer){.cdecl.}=
  let 
    e1 = arb.a.entID
    e2 = arb.b.entID
  if e1 < 1 or e2 < 1: return
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

proc handle_grav3 ( arb:PArbiter; space:PSpace; data:pointer ):bool {.cdecl.}=
  var gravSensor, shapeB : cp.PShape
  arb.getShapes gravSensor, shapeB
  
  template gravEnt: expr = space.room.getEnt(gravSensor.entID)
  
  let
    delta = (shapeB.getBody.getPos - gravSensor.getBody.getPos)
    dist = delta.len
    
    f = delta.normalizeSafe * -gravEnt[gravitySensor].force * (1.0 - (dist / gravEnt[gravitySensor].radius))

  shapeB.getBody.applyImpulse(f, vectorZero)

proc set_team (R: PRoom; ent: int; team: int) =
  if(var (has,T) = R.getTeam(team); has):
    debugECho "Player $# joined team $#".format( r.getEnt(ent).getName, T.name )
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
  
  debugEcho "New team $#".format( r.teamSys.teams[result] )

proc initRoom* (r: PRoom; gameData: PGameData) = 
  r.ents.newSeq 512
  r.ent_id = newIDgen[int]()
  r.gameData = gameData
  discard r.ent_id.get # use up 0

proc initRoom (room: PRoom; gameData: PGameData; name: string) =
  room.initRoom gamedata
  let j = gameData.rooms[name]
  room.name = j["name"].str
  
  block:
    template space: expr = room.physSys.space
    space.setUserdata(cast[pointer](room))
    
    space.addCollisionHandler(
      ct"gravity", 0.cuint, 
      presolve = handleGrav3
    )
    space.addCollisionHandler(
      0, 0,
      presolve = presolve_collision_cb,
      postSolve = postsolve_Collision_cb
    )
  
  proc importBounds (R:PROOM; J:PJSONNODE; W,H:VAR INT) =
    var bounds: seq[TVector] = @[]
    if j.kind == jObject:
      if j.hasKey("shape"):
        if j["shape"].str == "circle":
          let radius = j["radius"].toFloat
          let center = vector2d(radius, radius)
          let points = if j.hasKey("points"): j["points"].toInt else: 30
          for i in 0 .. < points:
            let p = polarVector2d(deg360 * (i / points), radius) + center
            bounds.add p
            w = max(p.x.int, w)
            h = max(p.y.int, h)
      else:
        w = j["width"].toInt
        h = j["height"].toInt
        bounds.add vector(0,0)
        bounds.add vector(w,0)
        bounds.add vector(w,h)
        bounds.add vector(0,h)
        
    elif j.kind == jArray:
      for b in j:
        let point = vector2d(b)
        bounds.add point.vector
        w = max(point.x.int, w)
        h = max(point.y.int, h)
    
    else:
      return
    
    r.bounds = just(newseq[cp.pshape](0))
    for i in 0 .. < bounds.len:
      const borderRadius = 10.0
      let
        b = r.physSys.space.getStaticBody
        v1 = bounds[i]
        v2 = bounds[(i+1) mod bounds.len]
        s = newSegmentShape(b, v1, v2, borderRadius)
      s.setElasticity 0.5
      r.bounds.val.add( r.physSys.space.addShape(s) )
  
  var 
    hasBounds = false
    worldSize: tuple[w,h: int]
    renderSysInitialized = false
  if j.hasKey"world":
    let w = j["world"]
    if w.hasKey"bounds":
      room.importBounds w["bounds"], worldsize.w, worldsize.h
    elif w.hasKey"width":
      worldSize.w = w["width"].toInt
      if w.hasKey"height":
        worldSize.h = w["height"].toInt
    
    if w.hasKey"partition":
      var ty: RoomPartitionType
      let w = w["partition"]
      case w["type"].str
      of "sectors":
        #rpt = RPTSectors
        var bb: TBB
        bb.width = w["width"].tofloat
        bb.height= w["height"].tofloat
        room.renderSys.partitiontype = RPTQuadTree
        room.renderSys.init
        renderSysInitialized = true
      else:
        #rpt = RPTBBtree
  
  elif j.hasKey"bounds":
    room.importBounds j["bounds"], worldSize.w,worldSize.h
  
  if not renderSysInitialized:
    room.renderSys.partitionType = RPTBBTREE
    room.renderSys.init
  
  room.w = worldSize.w
  room.h = worldSize.h
  
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

      var ent: PEntity
      ent = room.newEnt(entity_type)
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
      var ent: PEntity
      try:
        ent = room.newEnt(objTy)
      except EInvalidKey:
        echo "Entity not found $#".format( objTy )
        break

      ent.unserialize data, room
      room.addEnt(ent)

  if j.hasKey("objects"):
    let j = j["objects"]
    for obj in j:
      importObject(obj)
  else:
    echo "No objects in this room."
    

proc newRoom* (gamedata: PGameData; room: string) : Proom =
  result.new free
  echo"Creating a new room."
  result.initSystems
  result.initRoom gamedata, room

discard """ proc newRoom* (gamedata:PGameData): PRoom =
  # create basic room, only update and doom systems
  result.new free
  echo"Creating new anonymous room"
  result.initbasicsystems
  result.initRoom gamedata """
  
  

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

let playerType* = dom.getTypeinfo(Named, Owned, TeamMember, Radar, Position)

proc joinPlayer* (R: PRoom; name: string; ty = playerType): int =
  var ent = ty.newEntity
  #var ent = dom.newEntity(Named, Owned, TeamMember, Radar, Position)
  ent[Named].s = name
  ent[Radar].r = 512
  result = R.addEnt(ent)
  R.setPlayerTeam result, 0
  
  debugEcho "Player $# joined room $# (team $#)".format(
    r.getEnt(result).getName, r.name,
    R.getTeam(R.getEnt(result)[TeamMember].team)
  )

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
  var ent = r.newEnt(veh)
  dom.addComponents ent, Owned
  ent[Owned].by = player
  let vehicle_id = R.addEnt(ent)
  result = Just(vehicle_id)

  let spawnPoint = playerTeam.val.findRole(r, "spawn-point").firstMaybe
  if spawnPoint:
    let pos = r.getEnt(spawnPoint.val).getPos
    R.getEnt(vehicle_id).setPos pos
  else:
    debugEcho "Spawnpoint not found for team $#".format(playerTeam)


proc run* (s: PUpdateSystem; r:PRoom; dt: float) =
  for idx in 0 .. high(s.active):
    let id = s.active[idx]
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
  #r.renderSys.tree.update do (item: int) -> TBB: r.getEnt(item).getBB
  
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

proc postUpdate* (R:PROOM) =
  for id in r.updatesys.active:
    R.getEnt(id).postUpdate R
    R.renderSys.tree.update id, R.getEnt(id).getBB
    
proc update* (r: PRoom; dt:float) =
  r.updateSys.run(r, dt)
  r.physSys.step(dt)
  
  postUpdate r
  
  r.updateSys.execRCs r
  r.doomsys.run(r)

proc countAliveKind* (R:PRoom; kind:PJsonNode): int =
  proc contains (J:PJsonNode; str:string): bool =
    if j.kind == jArray and j[0].kind == jString and j[0].str == "group":
      if R.gamedata.groups.hasKey(j[1].str):
        result = str in R.gamedata.groups[j[1].str]
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
      for i in 1 .. < len(j):
        result = j[i].evalBool(R)
        if not result: return
        
      discard """ result = j[1].evalBool(R)
      if result: result = j[2].evalBool(R) """
      
    of "or":
      for i in 1 .. < len(j):
        result = j[i].evalBool(R)
        if result: return
      
      discard """ result = j[1].evalBool(R)
      if not result: result = j[2].evalBool(R) """
      
    of "not":
      result = not j[1].evalBool(R)



msgImpl(CollisionHandler, unserialize) do (J: PJsonNode; R: PRoom):
  if j.hasKey("CollisionHandler") and j["CollisionHandler"].kind == jObject:
    let j = j["CollisionHandler"]
    case j["action"].str
    of "warp":
      let p = point2d(j["position"])
      var warp_graphic = "warp-in"
      withKey(j, "warp-graphic", wg): warp_graphic = wg.str
      
      entity[collisionHandler].f = proc(self,other: PEntity) =
        other.setPos p
        let wg = warp_graphic
        other.scheduleRC do (x: PEntity; r: PRoom):
          var ent = r.newEnt(wg)
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
    var ent = r.newEnt(et.emitsJson)
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



msgImpl(Trail, update) do (dt: float) :
  entity[trail].timer -= dt
  if entity[trail].timer <= 0:
    entity.scheduleRC do (X: PEntity; R: PRoom):
      let x_id = x.id
      var ent = r.newEnt(x[trail].entity)
      ent.setPos r.getEnt(x_id).getPos
      r.addEnt(ent)
      r.getEnt(x_id)[trail].timer = r.getEnt(x_id)[trail].delay


msgImpl(AttachedVehicle,addToRoom) do (R:PROOM):
  let my_id = entity.id
  var attachs = entity[attachedVehicle].attachments
  for id in 0 .. high(attachs):
    var ent = R.newEnt(attachs[id].veh)
    dom.addComponents ent, Owned
    ent[Owned].by = my_id
    attachs[id].ent = R.addEnt(ent)
  R.getEnt(my_id)[attachedVehicle].attachments = attachs



msgImpl(ExplosionAnimation, on_explode) do :
  entity.scheduleRC do (X:PEntity; R:PRoom):
    var ent = R.newEnt(x[explosionAnimation].entity)
    ent.setPos x.getPos
    R.addEnt(ent)








