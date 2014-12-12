
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


import entoody,fowltek/idgen,fowltek/boundingbox

proc bb* (b: cp.TBB): boundingBox.TBB =
  bb(b.l.float, b.t.float, (b.r - b.l).float, (b.b - b.t).float)


proc addToSpace* (s: PSpace) {.multicast.}
proc removeFromSpace*(s: PSpace){.multicast.}

proc addToRoom* (R: PRoom) {.multicast.}
proc removeFromRoom*(R:PRoom){.multicast.}

proc impulse* (f: TVector2d) {.unicast.}

proc setPos* (p: TPoint2d) {.unicast.}
proc getPos* : TPoint2d {.unicast.}
proc getAngle*: float {.unicast.}
proc setVel* (v: TVector2d) {.unicast.}
proc getVel* : TVector2d {.unicast.}
proc getBody*: TMaybe[cp.PBody]{.unicast.}
proc getRadius*: TMaybe[float] {.unicast.}
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
proc postUpdate* (R:PRoom){.multicast.}
proc draw* (R: PRenderWindow) {.unicast.}

proc unserialize* (j: PJsonNode; R:PRoom) {.multicast.}

proc handleCollision* (other: PEntity) {.multicast.}
proc onCollide* (other: PEntity; handled: var bool) {.multicast.}

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

defMsg(RCC,schedule_rc) do (f: TRCC_CB):
  entity[RCC].commands.add f

proc execRCs* (ent: PEntity; r: PRoom) =
  if ent.hasComponent(RCC):
    if ent[RCC].commands.isNIL:
      echo "RCCS IS NIL WTF"
      echo ent.getName
      quit 1
    for c in ent[RCC].commands:
      c(ent, r)
    ent[RCC].clear


type
  Inventory* = object
    items: seq[PEntity]

defMsg(Inventory, accumMass) do (result:var float):
  for i in 0 .. < entity[Inventory].items.len:
    entity[Inventory].items[i].accumMass(result)




type
  Body* = object
    b*: cp.PBody
    s*: cp.PShape
Body.setDestructor do (e: PEntity):
  if not e[Body].s.isNil:
    free e[Body].s
  if not e[Body].b.isNil:
    free e[Body].b

defMsg(Body, getAngle) do -> float:
  entity[Body].b.getAngle.float
defMsg(Body, accumMass) do (result: var float):
  result += entity[Body].b.getMass.float
defMsg(Body, getRadius) do -> TMaybe[float]:
  Just(entity[Body].s.getCircleRadius.float)
defMsg(Body, calculateBB, 1000) do (result: var TBB):
  result.expandToInclude(entity[Body].s.getBB.bb)
defMsg(Body, getBody) do -> TMaybe[cp.PBody]:
  Maybe(entity[Body].b)

defMsg(Body, unserialize) do (j: PJsonNode; R:PRoom):
  if j.hasKey("Body"):
    let j = j["Body"]
    
    if j.hasKey("mass"):
      let mass = j["mass"].toFloat
      if entity[Body].b.isNIL:
        entity[Body].b = newBody(mass, 1.0)
      else:
        entity[Body].b.setMass mass

    if j.hasKey("shape"):
      if not entity[Body].s.isnil:
        let shape = entity[Body].s
        entity.scheduleRC do (x: PEntity; r: PRoom):
          #destroy the old shape
          r.physSys.space.removeShape(shape)
          free shape

      case j["shape"].str
      of "circle":
        let 
          mass = entity[Body].b.getMass
        var 
          radius:float
        radius.getFloat j, "radius", 30.0
        
        let 
          moment = momentForCircle(mass, radius, 0.0, cp.VectorZero)
        entity[Body].b.SetMoment(moment)
        
        let
          shape = newCircleShape(entity[Body].b, radius, cp.VectorZero)
        shape.setElasticity( 1.0 )
        entity[Body].s = shape
      else:
        quit "unk shape type: "& j["shape"].str
  
    if j.hasKey("elasticity"):
      entity[Body].s.setElasticity j["elasticity"].toFloat
  
  if j.hasKey("initial-impulse"):
    var vec = j["initial-impulse"].vector2d
    entity.impulse vec
  if j.hasKey("initial-position") and not entity[Body].b.isNil:
    entity.setPos j["initial-position"].point2d
  elif j.hasKey("Position") and not entity[Body].b.isNil:
    entity.setPos j["Position"].point2d

defMsg(Body, setPos) do (p: TPoint2d):
  if not entity[Body].b.isNil:
    entity[Body].b.setPos vector(p.x, p.y)
defMsg(Body, getPos) do -> TPoint2d:
  point2d(entity[Body].b.p)

defMsg(Body,setVel) do (v: TVector2d):
  entity[Body].b.setVel vector(v)
defMsg(Body, getVel) do -> TVector2d:
  vector2d(entity[Body].b.getVel)

defMsg(Body, addToSpace) do (s: PSpace):
  if not entity[Body].b.isNil:
    discard s.addBody(entity[Body].b)
    entity[Body].b.setUserdata cast[pointer](entity.id)
  if not entity[Body].s.isNil:
    discard s.addShape(entity[Body].s)
    entity[Body].s.setUserdata cast[pointer](entity.id)
defMsg(Body, removeFromSpace) do (s: PSpace):
  if not entity[Body].s.isNil:
    s.removeShape(entity[Body].s)
    reset entity[Body].s.data
  if not entity[Body].b.isNil:
    s.removeBody(entity[Body].b)
    reset entity[Body].b.data

defMsg(Body, impulse) do (f: TVector2d):
  entity[Body].b.applyImpulse(
    vector(f), VectorZero)

proc thrustFwd* {.unicast.}
proc thrustBckwd* {.unicast.}
proc turnRight* {.multicast.}
proc turnLeft* {.multicast.}
proc fire* (slot = 0) {.unicast.}

const thrust = 50.0
const turnspeed = 40.0
defMsg(Body, thrustFwd) do:
  entity[Body].b.applyImpulse(
    entity[Body].b.getAngle.vectorForAngle * entity.getFwSpeed,#thrust,
    VectorZero
  )
defMsg(Body, thrustBckwd) do:
  entity[Body].b.applyImpulse(
    -entity[Body].b.getAngle.vectorForAngle * entity.getRvSpeed,# thrust,
    VectorZero
  )
defMsg(Body,turnLeft) do:
  entity[Body].b.setTorque(- entity.getTurnspeed)
defMsg(Body,turnRight)do:
  entity[Body].b.setTorque(entity.getTurnspeed)

type InputController* = object
  forward*, backward*, turnLeft*, turnRight*: bool
  fireEmitter*, fireEmitter1*, fireEmitter2*,fireEmitter3*,fireEmitter4*,fireEmitter5*,fireEmitter6*: bool
  spec*,skillmenu*:bool
  
  aimTowards*: TMaybe[TPoint2d]
  selectedEmitter*: int

defMsg(InputController, update) do (dt: float) :
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
  if ic.fireEmitter2: entity.fire 2
  if ic.fireEmitter3: entity.fire 3
  if ic.fireEmitter4: entity.fire 4
  if ic.fireEmitter5: entity.fire 5
  if ic.fireEmitter6: entity.fire 6

type
  GravitySensor* = object
    shape: cp.PShape
    force*: float
    radius*:float
GravitySensor.requiresComponent Body

GravitySensor.setDestructor do (x:PEntity):
  if not x[GravitySensor].shape.isNil:
    free x[GravitySensor].shape

defMsg(GravitySensor, unserialize) do (j: PJsonNode; r:PRoom):
  withKey( j,"GravitySensor",s ):
    withKey( s,"radius",r ):
      let r = r.toFloat
      entity[GravitySensor].radius = r
    withKey( s,"force",f ):
      entity[GravitySensor].force = f.toFloat

defMsg(GravitySensor, addToSpace) do (s: PSpace):
  entity[GravitySensor].shape = s.addShape( newCircleShape ( entity[Body].b, entity[GravitySensor].radius, VectorZero ) )
  entity[GravitySensor].shape.setSensor true
  entity[GravitySensor].shape.setCollisionType ct"gravity"
  entity[GravitySensor].shape.setUserdata cast[pointer](entity.id)

defMsg(GravitySensor, removeFromSpace) do (s: PSpace):
  s.removeShape(entity[GravitySensor].shape)



proc on_expire {.multicast.}
proc expire* (x:PEntity) =
  x.on_expire
  x.scheduleRC do (X:PEntity; R:PRoom):
    R.doom X.id

proc on_explode  {.multicast.}
proc explode* (x:PEntity) =
  x.on_explode
  x.scheduleRC do (X:PEntity;R:PRoom):
    R.doom X.id



# draw scale (0.0 to 1.0)
proc getscale_pvt(result:var cfloat) {.unicast.}
proc getscale* (E: PEntity): TVector2f = 
  result.x = 1.0
  E.getscalePVT result.x
  result.y = result.x

type SpriteScale* = object
  s*:float
SpriteScale.componentInfo.name = "Scale"
defMsg(SpriteScale, unserialize)do(j:PjsonNode; R:PRoom):
  withKey(j, "Scale", s):
    entity[Spritescale].s = s.toFloat
defMsg(SpriteScale, getScalePVT, 1) do (result: var cfloat):
  result = entity[Spritescale].s


proc bbCentered* (p: TPoint2d; w, h: float): boundingbox.TBB =
  bb( p.x - (w/2) , p.y - (h/2) , w, h)

type
  Sprite* = object
    s: PSprite
    t: PTilesheet
    w,h: int
    dontRotate: bool

Sprite.setDestructor do (X:PEntity): 
  if not X[Sprite].s.isNil:
    destroy X[Sprite].s

defMsg(Sprite,unserialize) do (J:PJsonNode; R:PRoom):
  withKey(j, "Sprite", j):
    let sp = entity[sprite].addr
    withKey(j,"file",f):
      let t = tilesheet(f.str)
      sp.s = t.create(0,0)
      sp.w = t.rect.width
      sp.h = t.rect.height
      sp.t = t
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
      
defMsg(Sprite,draw) do (R:PRenderWindow):
  let s = entity[sprite].s
  s.setPosition entity.getPos.vec2f
  if not entity[sprite].dontRotate:
    s.setRotation entity.getAngle.radToDeg
  s.setScale entity.getScale
  R.draw s

defMsg(Sprite,calculateBB) do (result: var TBB):
  let scale = entity.getScale
  result.expandToInclude(
    bbCentered(
      entity.getPos, 
      entity[sprite].w.float * scale.x, 
      entity[sprite].h.float * scale.y
    )
  )

proc setRow* (S:VAR SPRITE; R:INT) =
  s.t.setRow s.s, r
proc setCol* (S:VAR SPRITE; C:INT) =
  s.t.setCol s.s, c

type
  SpriteColsAreAnimation* = object
    index*:int
    timer*,delay*:float
SpriteColsAreAnimation.requiresComponent Sprite

SpriteColsAreAnimation.setInitializer do (X:PENTITY):
  x[spriteColsAreAnimation].timer = 1.0
  x[spriteColsAreAnimation].delay = 1.0
defMsg(SpriteColsAreAnimation,unserialize) do (J:PJsonNode;R:PRoom):
  withKey( j,"SpriteColsAreAnimation",sa ):
    if sa.kind != jBool:
      let d = sa.toFloat
      entity[spriteColsAreAnimation].delay = d
      entity[spriteColsAreAnimation].timer = d
defMsg(SpriteColsAreAnimation,update) do (DT:FLOAT):
  let sa = entity[spriteColsAreAnimation].addr
  sa.timer -= dt
  if sa.timer <= 0:
    sa.timer = sa.delay
    sa.index = (sa.index + 1) mod entity[sprite].t.cols
    entity[sprite].setCol sa.index

type
  OneShotAnimation* = object
    index*: int
    delay*,timer*:float
OneShotAnimation.requiresComponent Sprite 

OneShotAnimation.setInitializer do (E: PEntity):
  let osa = e[oneshotanimation].addr
  osa.delay = 1.0
  osa.timer = osa.delay

defMsg(OneShotAnimation,unserialize) do (J: PJsonNOde; R:PRoom):
  withKey(j,"OneShotAnimation",osa):
    let d = osa.toFloat
    entity[oneShotAnimation].delay = d
    entity[oneShotAnimation].timer = d

defMsg(OneShotAnimation, update) do (dt: float):
  let osa = entity[oneShotAnimation].addr
  osa.timer -= dt
  if osa.timer <= 0:
    osa.timer = osa.delay
    osa.index.inc 1 
    if osa.index == entity[sprite].t.cols:
      entity.expire
      discard """ entity.scheduleRC do (X: PEntity; R: PRoom):
        r.doom(x.id) """
    else:
      entity[sprite].setCol osa.index


type SpriteRowsAreRotation* = object
SpriteRowsAreRotation.requiresComponent Sprite

defMsg(SpriteRowsAreRotation, unserialize) DO (J:PJSONNODE;R:PROOM):
  entity[sprite].dontRotate = true
  
defMsg(SpriteRowsAreRotation, postUpdate) do (R:PROOM):
  let row = int( (( entity.getAngle + DEG90 ) mod DEG360) / DEG360 * entity[sprite].t.rows.float )
  entity[sprite].setRow row

type SpriteColsAreRoll* = object
  roll: float
  rollRate: float
SpriteColsAreRoll.setInitializer do (X:PENTITY):
  X[SpriteColsAreRoll].rollRate = 0.2


defMsg(SpriteColsAreRoll, turnRight) do :
  entity[SpriteColsAreRoll].roll -= entity[SpriteColsAreRoll].rollRate
defMsg(SpriteColsAreRoll, turnLeft) do :
  entity[SpriteColsAreRoll].roll += entity[SpriteColsAreRoll].rollRate

defMsg(SpriteColsAreRoll, postUpdate) DO (R:PROOM):
  let rs = entity[spriteColsAreRoll].addr
  if rs.roll < -1: rs.roll = -1
  elif rs.roll > 1: rs.roll = 1
  else:         rs.roll *= 0.98
  let col = int( ( (rs.roll + 1.0) / 2.0) * (< entity[sprite].t.cols).float )
  entity[sprite].setCol col
  

discard """ type
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
 """

type
  Named* = object
    s*: string

defMsg(Named, unserialize) do (J: PJsonNode; R:PRoom):
  if J.hasKey("Named") and J["Named"].kind == jString:
    entity[Named].s = J["Named"].str
defMsg(Named, getName) do (result:var string):
  result = entity[named].s


type
  CollisionHandler* = object
    f*: proc(self, other: PEntity)

CollisionHandler.setInitializer do (E: PEntity):
  e[CollisionHandler].f = proc(s,o:PEntity) =
    discard
defMsg(CollisionHandler, handleCollision) do (other: PEntity) :
  entity[CollisionHandler].f(entity, other)


type Owned* = object
  by*: int
proc getOwner* : int {.unicast.}
proc setOwner* (ent:int) {.unicast.}
defMsg(Owned, getOwner) do -> int:
  return entity[Owned].by
defMsg(Owned, setOwner) do (ent:int):
  entity[Owned].by = ent


type Bouncy* = object
  bounces*: int

defMsg(Bouncy,presolveCollision) do (other:PEntity) -> bool:
  #
  
discard """ defMsg(Bouncy, handleCollision) do (other: PEntity; handled: var bool) :
  #if handled: return
  
  if other.hasComponent(Owned) and other[owned].by == entity.id:
    #handled = true
    return
    
  if entity[bouncy].bounces > 0:
    entity[bouncy].bounces.dec 1
    #handled = true
    return true # return true for do collision
  else:
    # explodes """


type ExplosionAnimation* = object
  entity*: PJsonNode

defMsg(ExplosionAnimation, unserialize) do (J:PJsonNode; R:PRoom):
  withKey( j, "ExplosionAnimation", j ):
    entity[explosionAnimation].entity = j


type ExplodesOnContact* = object

#msgImpl(ExplodesOnContact, handleCollision) DO (other:PEntity; handled:var bool):
  





type
  Emitter* = object
    e*: PEmitterType
    cooldown*: float
    mode*: EmitterMode
  EmitterMode* {.pure.}=enum
    manual, auto

proc unserialize (e: var Emitter; j: PjsonNode; R: PRoom) =
  if j.kind == jObject:
    if e.e.isNil:
      e.e = emitterTy("anonymous emitter", j)
      e.e.settle r.gameData.emitters
    
    
    if j.hasKey"mode":
      if j["mode"].str == "manual":
        e.mode = EmitterMode.manual
      else:
        e.mode = EmitterMode.auto
  
  elif j.kind == jString:
    e.e = r.gameData.emitters[j.str]


defMsg(Emitter,unserialize) do (J: PJsonNode; R:PRoom):
  withKey(j, "Emitter", j):
    entity[emitter].unserialize  j, r
    

# Emitter#update and #fire is in room.nim

type
  Emitters* = object
    ems*: seq[Emitter]

defMsg(Emitters, unserialize) do (J: PJsonNode; R: PRoom):
  withKey(j, "Emitters", j):
    entity[emitters].ems.newSeq j.len
    for i in 0 .. < len(j):
      entity[emitters].ems[i].unserialize j[i], r

type
  Position* = object
    p: TPoint2d
defMsg(Position,setPos) do (p: TPoint2d):
  entity[position].p = p
defMsg(Position,getPos) do -> TPoint2d:
  entity[position].p
defMsg(Position,unserialize) do (J: PJsonNode; R:PRoom):
  if j.hasKey("Position") and j["Position"].kind == jArray:
    entity[Position].p = point2d(j["Position"])
    echo entity[Position].p


type  
  Orientation* = object
    angle: float
defMsg(Orientation,getAngle) do -> float:
  entity[Orientation].angle

defMsg(Orientation,unserialize)do(J:PJsonNode; R:PRoom):
  if j.hasKey("Orientation"):
    entity[Orientation].angle = j["Orientation"].toFloat


import macros

template simpleComp(name): stmt {.immediate.} =
  type name * = object
    val: float
  defMsg(name, unserialize) do (J: PJsonNode; R:PRoom):
    if j.hasKey(astToStr(name)):
      entity[name].val = j[astToStr(name)].toFloat

simpleComp(AngularDampners)
defMsg(AngularDampners, update) do (dt: float):
  if(;var (has,b) = entity.getBody; has):
    b.setAngVel b.getAngVel * entity[angularDampners].val


type Actuators* = object
  turnSpeed*: float
defMsg(Actuators, unserialize) do (J:PJsonNode; R:PRoom):
  if j.hasKey"Actuators":
    entity[actuators].turnSpeed = j["Actuators"].toFloat
defMsg(Actuators,getTurnspeed) do -> float:
  return entity[actuators].turnspeed


type Thrusters* = object
  rvSpeed*, fwSpeed*:float
defMsg(Thrusters,unserialize) do(J:PJsonNOde; R:PRoom):
  withkey( j,"Thrusters",j ):
    if j.hasKey"fwspeed": entity[Thrusters].fwspeed = j["fwspeed"].toFloat
    if j.hasKey"rvspeed": 
      let rvspd = j["rvspeed"]
      if rvspd.kind == jInt and rvspd.num == -1:
        entity[Thrusters].rvspeed = entity[thrusters].fwspeed
      else:
        entity[Thrusters].rvspeed = j["rvspeed"].toFloat
defMsg(Thrusters, getFwSpeed) do ->float:
  return entity[thrusters].fwSpeed
defMsg(Thrusters,getRvSpeed) do ->float:
  return entity[thrusters].rvspeed

proc getZorder* : int {.unicast.}

type ZOrder* = object
  z*: int
defMsg(ZOrder, getZorder) do -> int:
  entity[ZOrder].z
defMsg(ZOrder, unserialize) do (J:PJsonNode; R:PRoom):
  if j.hasKey"ZOrder":
    entity[ZOrder].z = j["ZOrder"].toInt

type Parallax* = object
  offs*: float



type PlayerController* = object

type
  TeamMember* = object
    team*: int

proc getTeam* : TMaybe[int] {.unicast.}
defMsg(TeamMember, getTeam) do -> TMaybe[int] :
  result = Just( entity[TeamMember].team )


type
  Role* = object
    roles*: seq[string]

Role.setInitializer do (x:PEntity):
  x[role].roles.newSeq 0
defMsg(Role,unserialize) do (J:PJsonNode; R:PRoom):
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

defMsg(Lifetime,unserialize) do (J:PJsonNode; R:PRoom):
  withKey(j,"Lifetime",j):
    entity[Lifetime].time = j.toFloat
defMsg(Lifetime, update) do (dt:float):
  entity[Lifetime].time -= dt
  if entity[Lifetime].time <= 0:
    entity.expire

type
  VelocityLimit* = object
    limit: float

defMsg(VelocityLimit, unserialize) do (J:PJsonNode; R:PRoom):
  withKey(j,"VelocityLimit",j):
    entity[velocityLimit].limit = j.toFloat
defMsg(VelocityLimit, update) do (dt: float):
  let v = entity.getVel
  if v.len > entity[velocityLimit].limit:
    entity.setVel v * 0.95

type Radar* = object
  r*: int # radius

Radar.setInitializer do (X: PEntity):
  x[radar].r = 1000
proc bb* (R: Radar; P: TPoint2d): TBB =
  bb(
    p.x - (r.r / 2),
    p.y - (r.r / 2),
    r.r.float, r.r.float
  )


type BannedEntity* = object

type Battery* = object
  capacity*, current*: float
  start: TMaybe[float]
  regenRate*: float

defMsg(Battery,unserialize)do(j:pjsonnode;r:proom):
  withKey(j,"Battery",j):
    
    if j.hasKey("capacity"):
      entity[battery].capacity = j["capacity"].toFloat
    if j.HasKey("start"):
      entity[battery].start = Just(j["start"].toFloat)
    if j.haskey("regen-rate"):
      entity[battery].regenRate = j["regen-rate"].toFloat 

defMsg(battery,addtospace)do(s:pspace):
  if entity[battery].start.has:
    entity[battery].current = entity[battery].start.val
  else:
    entity[battery].current = entity[battery].capacity

defMsg(Battery,update)do(dt:float):
  entity[battery].current = min(entity[battery].capacity, entity[battery].current + (entity[battery].regenRate * dt))

proc secure_nrg (amt:float):bool {.unicast.}
proc get_energy* : float {.unicast.}
proc get_energy_pct* : float {.unicast.}

proc secureEnergy* (E:PEntity; amt:TMaybe[float]):bool {.inline.} =
  result = 
    if not(amt.has) or amt.val == 0: true
    else: e.secureNRG(amt.val)

defMsg(battery,secure_nrg)do(amt:float)->bool:
  if entity[battery].current >= amt:  
    entity[battery].current -= amt
    result = true
defMsg(battery,getenergy)do->float:
  return entity[battery].current
defMsg(battery,get_energy_pct)do->float:
  result = entity.getEnergy / entity[battery].capacity


type Trail* = object
  delay*,timer*: float
  entity*: PJsonNode

defMsg(Trail, unserialize) do (J:PJsonNode; R:PRoom):
  withKey(j, "Trail", j):
    if j.kind in {jString,jArray}:
      entity[trail].entity = j
    elif j.kind == jObject:
      withKey(J, "delay-ms", D): entity[trail].delay = d.toInt / 1000
      withKey(J, "delay", D): entity[trail].delay = d.toFloat
      entity[trail].timer = entity[trail].delay
      
      withKey(J, "entity", E): entity[trail].entity = E
# Trail#update is in room.nim

type RoomMember* = object
  R*: PRoom

defMsg(RoomMember,addToRoom) do (R:PRoom):
  entity[roomMember].r = r

type
  VehAttachPoint = tuple
    ent: int
    delta: TVector2d
    veh: PJsonNode
     
  AttachedVehicle* = object
    attachments*: seq[VehAttachPoint]

AttachedVehicle.requiresComponent RoomMember
AttachedVehicle.setInitializer do (X:PEntity):
  X[AttachedVehicle].attachments.newSeq 0

# AttachedVehicle#addToSpace is in room.nim
defMsg(AttachedVehicle,removeFromSpace)DO(R:PROOM):
  # doom its sub-ents
  for id in 0 .. high(entity[attachedVehicle].attachments):
    r.doom entity[attachedvehicle].attachments[id].ent

defMsg(AttachedVehicle,unserialize) do (J:PJSONNODE;R:PROOM):
  withkey(j,"AttachedVehicle",av):
    for item in av:
      var ap: VehAttachPoint
      withkey(item,"vehicle",v):
        ap.veh = v
      withkey(item,"delta",d):
        ap.delta = d.vector2d
      entity[attachedVehicle].attachments.add ap
defMsg(AttachedVehicle,postUpdate) do (R:PROOM) : 
  let ent_pos = entity.getPos
  let ent_angle=entity.getAngle
  for i in 0 .. < entity[attachedvehicle].attachments.len:
    template attach : expr = entity[attachedVehicle].attachments[i]
    template veh : expr = entity[RoomMember].r.getEnt(attach.ent)
    var delta = attach.delta
    delta.rotate ent_angle
    veh.setPos ent_pos + delta




type ClientControlled* = object
  client*: int

import enet
type EnetPeer* = object
  p*: PPeer

