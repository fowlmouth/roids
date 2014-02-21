
import 
  strutils, csfml, csfml_colors,basic2d,json,math,
  tables,
  fowltek/maybe_t
import chipmunk as cp except TBB
import
  private/tilesheet, private/common,
  private/room_interface, private/emitter_type


var collisionTypes = initTable[string, cuint](64)
var next = 0.cuint
proc ct* (s: string): cuint = 
  if not collisionTypes.hasKey(s):
    collisionTypes[s] = next
    next += 1
  return collisionTypes[s]
discard ct("default")


import fowltek/entitty,fowltek/idgen,fowltek/boundingbox

proc bb* (b: cp.TBB): boundingBox.TBB =
  bb(b.l.float, b.t.float, (b.r - b.l).float, (b.b - b.t).float)


proc addToSpace* (s: PSpace) {.multicast.}
proc removeFromSpace*(s: PSpace){.multicast.}

proc impulse* (f: TVector2d) {.unicast.}

proc setPos* (p: TPoint2d) {.unicast.}
proc getPos* : TPoint2d {.unicast.}
proc getAngle*: float {.unicast.}
proc setVel* (v: TVector2d) {.unicast.}
proc getVel* : TVector2d {.unicast.}
proc getBody*: TMaybe[cp.PBody]{.unicast.}
proc getTurnspeed* : float {.unicast.}
proc getFwSpeed* : float {.unicast.}
proc getRvSpeed* : float {.unicast.}

proc calculateBB* (result: var TBB) {.multicast.}
proc getBB* (entity:PEntity): TBB =
  let p = entity.getPos
  result.left = p.x
  result.top = p.y
  entity.calculateBB result

proc update* (dt: float) {.multicast.}
proc draw* (R: PRenderWindow) {.unicast.}

proc unserialize* (j: PJsonNode; R:PRoom) {.multicast.}

proc handleCollision* (other: PEntity) {.multicast.}

proc getName* (result: var string) {.unicast.}
proc getName* (e: PEntity): string =
  e.getName result
  if result.isNil:
    result = "entity #"
    result.add($e.id)

proc accumMass* (result: var float) {.multicast.}


# room command chain
# a queue of functions run so the entity has access to the room it is in
type
  TRCC_CB* = proc(x: PEntity; r: PRoom)
  RCC* = object
    commands*: seq[TRCC_CB]

proc scheduleRC* (f: TRCC_CB) {.unicast.}


RCC.setInitializer do (x: PEntity):
  x[RCC].commands.newSeq 0
  
proc clear* (R: var RCC)= 
  R.commands.setLen 0

msgImpl(RCC,schedule_rc) do (f: TRCC_CB):
  entity[RCC].commands.add f

proc execRCs* (ent: PEntity; r: PRoom) =
  if ent.hasComponent(RCC):
    for c in ent[RCC].commands:
      c(ent, r)
    ent[RCC].clear


type
  Inventory* = object
    items: seq[TEntity]

msgImpl(Inventory, accumMass) do (result:var float):
  for i in 0 .. < entity[inventory].items.len:
    entity[inventory].items[i].accumMass(result)




type
  Body* = object
    b*: cp.PBody
    s*: cp.PShape
Body.setDestructor do (E: PEntity):
  if not e[body].s.isNil:
    free e[body].s
  if not e[body].b.isNil:
    free e[body].b

msgImpl(Body, getAngle) do -> float:
  entity[body].b.getAngle.float
msgImpl(Body, getMass) do -> float:
  entity[body].b.getMass.float
msgImpl(Body, calculateBB, 1000) do (result: var TBB):
  result.expandToInclude(entity[body].s.getBB.bb)
msgImpl(Body, getBody) do -> TMaybe[cp.PBody]:
  maybe(entity[body].b)

msgImpl(Body, unserialize) do (J: PJsonNode; R:PRoom):
  if j.hasKey("Body"):
    let j = j["Body"]
    
    if j.hasKey("mass"):
      let mass = j["mass"].toFloat
      if entity[body].b.isNIL:
        entity[body].b = newBody(mass, 1.0)
      else:
        entity[body].b.setMass mass

    if j.hasKey("shape"):
      if not entity[body].s.isnil:
        let shape = entity[body].s
        entity.scheduleRC do (x: PEntity; r: PRoom):
          #destroy the old shape
          r.physSys.space.removeShape(shape)
          free shape

      case j["shape"].str
      of "circle":
        let 
          mass = entity[body].b.getMass
        var 
          radius:float
        radius.getFloat j, "radius", 30.0
        
        let 
          moment = momentForCircle(mass, radius, 0.0, vectorZero)
        entity[body].b.setMoment(moment)
        
        let
          shape = newCircleShape(entity[body].b, radius, vectorZero)
        shape.setElasticity( 1.0 )
        entity[body].s = shape
      else:
        quit "unk shape type: "& j["shape"].str
  
    if j.hasKey("elasticity"):
      entity[body].s.setElasticity j["elasticity"].toFloat
  
  if j.hasKey("initial-impulse"):
    var vec = j["initial-impulse"].vector2d
    entity.impulse vec
  if j.hasKey("initial-position") and not entity[body].b.isNil:
    entity.setPos j["initial-position"].point2d
  elif j.hasKey("Position") and not entity[body].b.isNil:
    entity.setPos j["Position"].point2d

msgImpl(Body, setPos) do (p: TPoint2d):
  if not entity[body].b.isNil:
    entity[body].b.setPos vector(p.x, p.y)
msgImpl(Body, getPos) do -> TPoint2d:
  point2d(entity[body].b.p)

msgImpl(Body,setVel) do (v: TVector2d):
  entity[body].b.setVel vector(v)
msgImpl(Body, getVel) do -> TVector2d:
  vector2d(entity[Body].b.getVel)

msgImpl(Body, addToSpace) do (s: PSpace):
  if not entity[body].b.isNil:
    discard s.addBody(entity[body].b)
    entity[body].b.setUserdata cast[pointer](entity.id)
  if not entity[body].s.isNil:
    discard s.addShape(entity[body].s)
    entity[body].s.setUserdata cast[pointer](entity.id)
msgImpl(Body, removeFromSpace) do (s: PSpace):
  if not entity[body].s.isNil:
    s.removeShape(entity[body].s)
    reset entity[body].s.data
  if not entity[body].b.isNil:
    s.removeBody(entity[body].b)
    reset entity[body].b.data

msgImpl(Body, impulse) do (f: TVector2d):
  entity[Body].b.applyImpulse(
    vector(f), vectorZero)

proc thrustFwd* {.unicast.}
proc thrustBckwd* {.unicast.}
proc turnRight* {.multicast.}
proc turnLeft* {.multicast.}
proc fire* (slot = 0) {.unicast.}

const thrust = 50.0
const turnspeed = 40.0
msgImpl(Body, thrustFwd) do:
  entity[body].b.applyImpulse(
    entity[Body].b.getAngle.vectorForAngle * entity.getFwSpeed,#thrust,
    vectorZero
  )
msgImpl(Body, thrustBckwd) do:
  entity[body].b.applyImpulse(
    -entity[body].b.getAngle.vectorForAngle * entity.getRvSpeed,# thrust,
    vectorZero
  )
msgImpl(Body,turnLeft) do:
  entity[body].b.setTorque(- entity.getTurnspeed)
msgImpl(Body,turnRight)do:
  entity[body].b.setTorque(entity.getTurnspeed)

type InputController* = object
  forward*, backward*, turnLeft*, turnRight*: bool
  fireEmitter*, fireEmitter1*: bool
  spec*,skillmenu*:bool
  
  aimTowards*: TMaybe[TPoint2d]
  selectedEmitter*: int

msgImpl(InputController, update) do (dt: float) :
  let ic = entity[InputController].addr
  if ic.forward:
    entity.thrustFwd
  elif ic.backward:
    entity.thrustBckwd
  if ic.turnLeft:
    entity.turnLeft
  elif ic.turnRight:
    entity.turnRight
  if ic.fireEmitter:
    entity.fire 0
  if ic.fireEmitter1:
    entity.fire 1

type
  GravitySensor* = object
    shape: cp.PShape
    force*: float
GravitySensor.requiresComponent Body

msgImpl(GravitySensor, unserialize) do (J: PJsonNode; R:PRoom):
  if j.hasKey("GravitySensor"):
    let j = j["GravitySensor"]
    var radius: float
    radius.getFloat j, "radius", 500.0
    entity[gravitysensor].force.getFloat j, "force", 1000.0
    entity[gravitysensor].shape = newCircleShape(entity[Body].b, radius, vectorZero)
    entity[gravitysensor].shape.setSensor true
    entity[gravitysensor].shape.setCollisionType(ct"gravity")

msgImpl(GravitySensor, addToSpace) do (S: PSpace):
  discard s.addShape( entity[Gravitysensor].shape)
  entity[gravitySensor].shape.setUserdata cast[pointer](entity.id)
msgImpl(GravitySensor, removeFromSpace) do (S: PSpace):
  s.removeShape(entity[gravitySensor].shape)





# draw scale (0.0 to 1.0)
proc getscale_pvt(result:var cfloat) {.unicast.}
proc getscale* (E: PEntity): TVector2f = 
  result.x = 1.0
  E.getscalePVT result.x
  result.y = result.x

type SpriteScale* = object
  s*:float
SpriteScale.componentInfo.name = "Scale"
msgImpl(SpriteScale, unserialize)do(J:PjsonNode; R:PRoom):
  withKey(j, "Scale", s):
    entity[spritescale].s = j["Scale"].toFloat
msgImpl(SpriteScale, getScalePVT, 1) do (result: var cfloat):
  result = entity[spritescale].s


proc bbCentered* (p: TPoint2d; w, h: float): boundingbox.TBB =
  bb( p.x - (w/2) , p.y - (h/2) , w, h)

type
  Sprite* = object
    s: PSprite
    w,h: int

Sprite.setDestructor do (X:PEntity): 
  if not X[Sprite].s.isNil:
    destroy X[Sprite].s

msgImpl(Sprite,unserialize) do (J:PJsonNode; R:PRoom):
  withKey(j, "Sprite", j):
    let sp = entity[sprite].addr
    withKey(j,"file",f):
      let t = tilesheet(f.str)
      sp.s = t.create(0,0)
      sp.w = t.rect.width
      sp.h = t.rect.height
    withkey(j,"origin",j):
      if not sp.s.isNil:
        sp.s.setOrigin vec2f(point2d(j))
    withKey(j,"repeated-texture",rt):
      if not sp.s.isNil:
        sp.s.getTexture.setRepeated(rt.bval)
    withkey(j,"texture-rect-size",trs):
      let sz = trs.point2d
      var r = sp.s.getTextureRect
      r.width=sz.x.cint
      r.height=sz.y.cint
      sp.s.setTextureRect r
      
msgImpl(Sprite,draw) do (R:PRenderWindow):
  let s = entity[sprite].s
  s.setPosition entity.getPos.vec2f
  s.setRotation entity.getAngle.radToDeg
  s.setScale entity.getScale
  R.draw s

msgImpl(Sprite,calculateBB) do (result: var TBB):
  let scale = entity.getScale
  result.expandToInclude(
    bbCentered(
      entity.getPos, 
      entity[sprite].w.float * scale.x, 
      entity[sprite].h.float * scale.y
    )
  )


type
  AnimatedSprite = object 
    t: PTilesheet
    index: int
    timer: float
    delay: float

AnimatedSprite.setInitializer do (e: PEntity):
  e[animatedsprite] = AnimatedSprite(timer: 1.0, delay: 1.0, index: 0)

msgImpl(AnimatedSprite, unserialize) do (j: PJsonNode; R:PRoom):
  if j.hasKey("AnimatedSprite"):
    let j = j["AnimatedSprite"]
    let sp = entity[animatedsprite].addr
    
    withKey(j, "file", f):
      sp.t = tilesheet(f.str)
    withKey(j, "delay", d):
      sp.delay = d.toFloat
      sp.timer = sp.delay
    withKey(j, "delay-ms", d):
      sp.delay = d.toFloat / 1000
      sp.timer = sp.delay

msgImpl(AnimatedSprite, update) do (dt: float):
  let sp = entity[animatedsprite].addr
  sp.timer -= dt
  if sp.timer < 0:
    sp.timer = sp.delay
    sp.index = (sp.index + 1) mod sp.t.cols

msgImpl(AnimatedSprite, draw, 9001) do (R: PRenderWindow):
  var s = entity[animatedsprite].t.create(0,entity[animatedsprite].index)
  s.setPosition entity.getPos.vec2f 
  s.setRotation entity.getAngle.radToDeg
  s.setScale entity.getScale
  R.draw s
  destroy s

msgImpl(AnimatedSprite, calculateBB) do (result:var TBB):
  let scale = entity.getScale
  result.expandToInclude(bbCentered(
    entity.getPos,
    entity[animatedsprite].t.rect.width.float * scale.x, 
    entity[animatedsprite].t.rect.height.float * scale.y
  ))

type
  OneShotAnimation* = object
    t*: PTilesheet
    index*: int
    delay*: float
    timer*: float

OneShotAnimation.setInitializer do (E: PEntity):
  let osa = e[oneshotanimation].addr
  osa.delay = 1.0
  osa.timer = osa.delay

msgImpl(OneShotAnimation,unserialize) do (J: PJsonNOde; R:PRoom):
  if j.hasKey("OneShotAnimation"):
    let j = j["OneShotAnimation"]
    let sp = entity[oneshotanimation].addr
    withKey(j, "file", f):
      sp.t = tilesheet(f.str)
    withKey(j, "delay-ms", d):
      sp.delay = d.toFloat / 1000
      sp.timer = sp.delay
    withKey(j, "delay", d):
      sp.delay = d.toFloat
      sp.timer = sp.delay

msgImpl(OneShotAnimation,draw,9001) do (R: PRenderWindow):
  let s = entity[oneshotanimation].t.create(0, entity[oneshotanimation].index)
  s.setPosition entity.getPos.vec2f
  s.setRotation entity.getAngle.radToDeg
  s.setScale entity.getScale
  R.draw s
  destroy s

msgImpl(OneShotAnimation, update) do (dt: float):
  let osa = entity[oneShotAnimation].addr
  osa.timer -= dt
  if osa.timer <= 0:
    osa.timer = osa.delay
    osa.index = (osa.index + 1)
    if osa.index == osa.t.cols:
      entity.scheduleRC do (X: PEntity; R: PRoom):
        r.doom(x.id)

type
  RollSprite* = object
    t: PTilesheet
    roll: float

msgImpl(RollSprite, unserialize) do (J: PJsonNode; R:PRoom):
  if J.hasKey("RollSprite"):
    let j = j["RollSprite"]
    entity[rollSprite].t = tilesheet(j["file"].str)
msgImpl(RollSprite, draw, 9001) do (R: PRenderWindow):
  # roll is based the column, -1.0 is column 0, 1.0 is t.cols
  let rs = entity[rollSprite].addr
  
  let
    col = int( ( (rs.roll + 1.0) / 2.0) * (<rs.t.cols).float )
    row = int( (( entity.getAngle + DEG90 ) mod DEG360) / DEG360 * rs.t.rows.float )
  
  let 
    s = rs.t.create(row, col)
  s.setPosition entity.getPos.vec2f
  r.draw s
  destroy s

msgImpl(RolLSprite, turnRight) do :
  entity[rollSprite].roll -= 0.2
msgImpl(RollSprite, turnLeft) do :
  entity[rollSprite].roll += 0.2
msgImpl(RollSprite, update) do (dt: float):
  let rs = entity[rollSprite].addr
  if rs.roll < -1: rs.roll = -1
  elif rs.roll > 1: rs.roll = 1
  else:         rs.roll *= 0.98


type
  Named* = object
    s*: string

msgImpl(Named, unserialize) do (J: PJsonNode; R:PRoom):
  if J.hasKey("Named") and J["Named"].kind == jString:
    entity[Named].s = J["Named"].str
msgImpl(Named, getName) do (result:var string):
  result = entity[named].s


type
  CollisionHandler* = object
    f*: proc(self, other: PEntity)

CollisionHandler.setInitializer do (E: PEntity):
  e[CollisionHandler].f = proc(s,o:PEntity) =
    discard
msgImpl(CollisionHandler, handleCollision) do (other: PEntity) :
  entity[CollisionHandler].f(entity, other)








type
  Emitter* = object
    e*: PEmitterType
    cooldown*: float
    mode*: EmitterMode
  EmitterMode* {.pure.}=enum
    manual, auto

proc unserialize (e: var Emitter; j: PjsonNode; R: PRoom) =
  if j.kind == jObject:
    e.e = emitterTy("anonymous emitter", j)
    
    if j.hasKey"mode":
      if j["mode"].str == "manual":
        e.mode = EmitterMode.manual
      else:
        e.mode = EmitterMode.auto
  elif j.kind == jString:
    e.e = r.gameData.emitters[j.str]


msgImpl(Emitter,unserialize) do (J: PJsonNode; R:PRoom):
  withKey(j, "Emitter", j):
    entity[emitter].unserialize j, r
    

# Emitter#update and #fire is in room.nim

type
  Emitters* = object
    ems*: seq[Emitter]

msgImpl(Emitters, unserialize) do (J: PJsonNode; R: PRoom):
  withKey(j, "Emitters", j):
    entity[emitters].ems.newSeq j.len
    for i in 0 .. < len(j):
      entity[emitters].ems[i].unserialize j[i], r

type
  Position* = object
    p: TPoint2d
msgImpl(Position,setPos) do (p: TPoint2d):
  entity[position].p = p
msgImpl(Position,getPos) do -> TPoint2d:
  entity[position].p
msgImpl(Position,unserialize) do (J: PJsonNode; R:PRoom):
  if j.hasKey("Position") and j["Position"].kind == jArray:
    entity[Position].p = point2d(j["Position"])
    echo entity[Position].p


type  
  Orientation* = object
    angle: float
msgImpl(Orientation,getAngle) do -> float:
  entity[Orientation].angle

msgIMpl(Orientation,unserialize)do(J:PJsonNode; R:PRoom):
  if j.hasKey("Orientation"):
    entity[Orientation].angle = j["Orientation"].toFloat


import macros

template simpleComp(name): stmt {.immediate.} =
  type name * = object
    val: float
  msgImpl(name, unserialize) do (J: PJsonNode; R:PRoom):
    if j.hasKey(astToStr(name)):
      entity[name].val = j[astToStr(name)].toFloat

simpleComp(AngularDampners)
msgImpl(AngularDampners, update) do (dt: float):
  if(;var (has,b) = entity.getBody; has):
    b.setAngVel b.getAngVel * entity[angularDampners].val


type Actuators* = object
  turnSpeed*: float
msgImpl(Actuators, unserialize) do (J:PJsonNode; R:PRoom):
  if j.hasKey"Actuators":
    entity[actuators].turnSpeed = j["Actuators"].toFloat
msgImpl(Actuators,getTurnspeed) do -> float:
  return entity[actuators].turnspeed


type Thrusters* = object
  rvSpeed*, fwSpeed*:float
msgImpl(Thrusters,unserialize) do(J:PJsonNOde; R:PRoom):
  if j.hasKey"Thrusters" and j["Thrusters"].kind == jObject:
    let j = j["Thrusters"]
    if j.hasKey"fwspeed": entity[Thrusters].fwspeed = j["fwspeed"].toFloat
    if j.hasKey"rvspeed": 
      let rvspd = j["rvspeed"]
      if rvspd.kind == jInt and rvspd.num == -1:
        entity[Thrusters].rvspeed = entity[thrusters].fwspeed
      else:
        entity[Thrusters].rvspeed = j["rvspeed"].toFloat
msgImpl(Thrusters, getFwSpeed) do ->float:
  return entity[thrusters].fwSpeed
msgImpl(Thrusters,getRvSpeed) do ->float:
  return entity[thrusters].rvspeed

proc getZorder* : int {.unicast.}

type ZOrder* = object
  z*: int
msgImpl(ZOrder, getZorder) do -> int:
  entity[ZOrder].z
msgImpl(ZOrder, unserialize) do (J:PJsonNode; R:PRoom):
  if j.hasKey"ZOrder":
    entity[ZOrder].z = j["ZOrder"].toInt

type Parallax* = object
  offs*: float



type Owned* = object
  by*: int
proc getOwner* : int {.unicast.}
proc setOwner* (ent:int) {.unicast.}
msgImpl(Owned, getOwner) do -> int:
  return entity[Owned].by
msgImpl(Owned, setOwner) do (ent:int):
  entity[Owned].by = ent

type PlayerController* = object

type
  TeamMember* = object
    team*: int

type
  Role* = object
    roles*: seq[string]

Role.setInitializer do (x:PEntity):
  x[role].roles.newSeq 0
msgimpl(Role,unserialize) do (J:PJsonNode; R:PRoom):
  withKey(j,"Role",j):
    if j.kind == jArray:
      for j_object in j.items:
        entity[role].roles.add j_object.str
    elif j.kind == jString:
      entity[role].roles.add(j.str)

proc hasRole* (x: PEntity; r: string): bool =
  x.hasComponent(Role) and x[Role].roles.find(r) != -1


type
  Lifetime* = object
    time*: float

msgImpl(Lifetime,unserialize) do (J:PJsonNode; R:PRoom):
  withKey(j,"Lifetime",j):
    entity[Lifetime].time = j.toFloat
msgImpl(Lifetime, update) do (dt:float):
  entity[Lifetime].time -= dt
  if entity[Lifetime].time <= 0:
    entity.scheduleRC do (X: PEntity; R: PRoom):
      r.doom(x.id)

type
  VelocityLimit* = object
    limit: float

msgImpl(VelocityLimit, unserialize) do (J:PJsonNode; R:PRoom):
  withKey(j,"VelocityLimit",j):
    entity[velocityLimit].limit = j.toFloat
msgIMpl(VelocityLimit, update) do (dt: float):
  let v = entity.getVel
  if v.len > entity[velocityLimit].limit:
    entity.setVel v * 0.95

type Radar* = object
  r*: float # range

Radar.setInitializer do (X: PEntity):
  x[radar].r = 1000.0
proc bb* (R: Radar; P: TPoint2d): TBB =
  bb(
    p.x - (r.r / 2),
    p.y - (r.r / 2),
    r.r, r.r
  )


type BannedEntity* = object

type Battery* = object
  capacity*, current*: float
  start: TMaybe[float]
  regenRate*: float

msgImpl(Battery,unserialize)do(j:pjsonnode;r:proom):
  withKey(j,"Battery",j):
    
    if j.hasKey("capacity"):
      entity[battery].capacity = j["capacity"].toFloat
    if j.HasKey("start"):
      entity[battery].start = just(j["start"].toFloat)
    if j.haskey("regen-rate"):
      entity[battery].regenRate = j["regen-rate"].toFloat 

msgimpl(battery,addtospace)do(s:pspace):
  if entity[battery].start.has:
    entity[battery].current = entity[battery].start.val
  else:
    entity[battery].current = entity[battery].capacity

msgImpl(Battery,update)do(dt:float):
  entity[battery].current = min(entity[battery].capacity, entity[battery].current + (entity[battery].regenRate * dt))

proc secure_nrg (amt:float):bool {.unicast.}
proc get_energy* : float {.unicast.}
proc get_energy_pct* : float {.unicast.}

proc secureEnergy* (E:PEntity; amt:TMaybe[float]):bool {.inline.} =
  result = 
    if not(amt.has) or amt.val == 0: true
    else: e.secureNRG(amt.val)

msgimpl(battery,secure_nrg)do(amt:float)->bool:
  if entity[battery].current >= amt:  
    entity[battery].current -= amt
    result = true
msgImpl(battery,getenergy)do->float:
  return entity[battery].current
msgImpl(battery,get_energy_pct)do->float:
  result = entity.getEnergy / entity[battery].capacity

