
import strutils, csfml, csfml_colors,basic2d,json,math
import fowltek/maybe_t
import chipmunk as cp

proc ff* (f: float; prec = 2): string = formatFloat(f, ffDecimal, prec)

# the penalty for having sfml vectors and chipmunk vectors
proc vector* [T: TNumber] (x, y: T): TVector = 
  result.x = x.cpfloat
  result.y = y.cpfloat
proc vector* (v: TVector2d): TVector =
  result.x = v.x
  result.y = v.y
proc vector* (v: TPoint2d): TVector = 
  result.x = v.x
  result.y = v.y
proc vec2f* (v: TVector): TVector2f = TVector2f(x: v.x, y: v.y)
proc vec2f* (v: TPoint2d): TVector2f = TVector2f(x: v.x, y: v.y)
proc vector2d* (v: TVector): TVector2d =
  result.x = v.x
  result.y = v.y

when not TVectorIsTVector2d:
  proc point2d* (v: TVector): TPoint2d =
    point2d(v.x, v.y)
proc point2d* (v: TVector2d): TPoint2d=
  point2d(v.x, v.y)
proc point2d* (p: TVector2i): TPoint2d = point2d(p.x.float, p.y.float)

proc distance*(a, b: TVector): float {.inline.} =
  return sqrt(pow(a.x - b.x, 2.0) + pow(a.y - b.y, 2.0))

proc `$`* (v: TVector2d): string =
  "($1,$2) $3".format(v.x.ff, v.y.ff, v.angle.radToDeg.ff) 

proc toggle* (switch: var bool){.inline.}=switch = not switch

proc toInt* (n: PJSonNode): int =
  case n.kind
  of jINT:
    result = n.num.int
  else:
    echo "this is not an int: ", n

proc toFloat* (n: PJsonNode): float =
  case n.kind
  of jInt:
    result = n.num.float
  of jFloat:
    result = n.fnum.float
  of jString:
    case n.str
    of "random":
      result = random(1.0)
    of "infinity":
      result = 1/0
  of jArray:
    case n[0].str
    of "random":
      # random(x) 
      result = random(n[1].toFloat)
    of "degrees":
      # degToRad(x)
      result = degToRad(n[1].toFloat)

  else:
    echo "Not a float value: ", n
proc getFloat* (result: var float; j: PJsonNode; key: string, default = 0.0) =
  if j.kind == JObject and j.hasKey(key):
    result = j[key].toFloat
  else:
    when defined(Debug):
      echo "Missing float key ",key
    result = default

proc vector2d* (n: PJSonNode): TVector2d =
  if n.kind == jString:
    case n.str
    of "random-direction":
      result = polarVector2d(deg360.random, 1.0)
    return
  
  assert n.kind == jArray
  if n[0].kind == jString:
    case n[0].str
    of "direction-degrees":
      result = polarVector2d(n[1].toFloat.degToRad, 1.0)
    
    of "v_*_f", "mul_f":
      result = n[1].vector2d * n[2].toFloat
    else:
      discard
    return
  
  result.x = n[0].toFloat
  result.y = n[1].toFloat
proc point2d* (n: PJsonNode): TPoint2d =
  assert n.len == 2
  result.x = n[0].toFloat
  result.y = n[1].toFLoat
  
proc getPoint* (result: var TPoint2d; j: PJsonNode; key: string; default = point2d(0,0)) =
  if j.kind == JObject and j.hasKey(key):
    result = point2d(j[key])
  else:
    result = default

proc getInt* (result:var int; j:PJsonNode; key:string; default = 0) =
  if j.kind == JObject and j.hasKey(key):
    case j[key].kind
    of jInt:
      result = j[key].num.int
    of jFloat:
      result = j[key].fnum.int
    else:
      echo "Not an int value: ", j[key]
      result = default
  else:
    when defined(Debug):
      echo "Missing int key ", key
    result = default


import tables

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
  (b.l.float, b.t.float, (b.r - b.l).float, (b.b - b.t).float)


proc addToSpace* (s: PSpace) {.multicast.}
proc removeFromSpace*(s: PSpace){.multicast.}

proc impulse* (f: TVector2d) {.unicast.}

proc setPos* (p: TPoint2d) {.unicast.}
proc getPos* : TPoint2d {.unicast.}
proc getAngle*: float {.unicast.}
proc getVel* : TVector2d {.unicast.}
proc getBB* : boundingbox.TBB {.unicast.}
proc getBody*: TMaybe[cp.PBody]{.unicast.}
proc getTurnspeed* : float {.unicast.}
proc getFwSpeed* : float {.unicast.}
proc getRvSpeed* : float {.unicast.}


proc update* (dt: float) {.multicast.}
proc draw* (R: PRenderWindow) {.unicast.}

proc unserialize* (j: PJsonNode) {.multicast.}

proc handleCollision* (other: PEntity) {.multicast.}

proc getName* (result: var string) {.unicast.}
proc getName* (e: PEntity): string =
  e.getName result
  if result.isNil:
    result = "entity #"
    result.add($e.id)

proc accumMass* (result: var float) {.multicast.}

type
  Inventory* = object
    items: seq[TEntity]

msgImpl(Inventory, accumMass) do (result:var float):
  for i in 0 .. < entity[inventory].items.len:
    entity[inventory].items[i].accumMass(result)


import private/room_interface

# room command chain
# a queue of functions run so the entity has access to the room it is in

type
  TRCC_CB* = proc(x: PEntity; r: PRoom)
  RCC* = object
    commands*: seq[TRCC_CB]

proc scheduleRC* (f: TRCC_CB) {.unicast.}



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
msgImpl(Body, getBB) do -> boundingbox.TBB:
  bb(entity[body].s.getBB)
msgImpl(Body, getBody) do -> TMaybe[cp.PBody]:
  maybe(entity[body].b)

msgImpl(Body, unserialize) do (J: PJsonNode):
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
proc fire* {.unicast.}

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
  fireEmitter*: bool
  spec*,skillmenu*:bool
  aimTowards*: TMaybe[TPoint2d]

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
    entity.fire

type
  GravitySensor* = object
    shape: cp.PShape
    force*: float
GravitySensor.requiresComponent Body

msgImpl(GravitySensor, unserialize) do (J: PJsonNode):
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
  


import os, re
type
  PTilesheet* = ref object
    file*: string
    tex*: PTexture
    rect*: TIntRect
    rows*,cols*: int

proc create* (t: PTilesheet; row, col: int): PSprite =
  result = newSprite()
  result.setTexture t.tex, false
  var r = t.rect
  r.left = cint(col * r.width)
  r.top = cint(row * r.height)
  result.setTextureRect r 
  result.setOrigin vec2f(r.width / 2, r.height / 2)

var 
  cache = initTable[string,PTilesheet](64)
  imageFilenamePattern = re".+_(\d+)x(\d+)\.\S{3,4}"
const
  assetsDir = "assets"

proc free* (T: PTilesheet) =
  destroy t.tex

proc tilesheet* (file: string): PTilesheet =
  result = cache[file]
  if not result.isNil:
    return
  
  var img = newImage(assetsdir / file)
  
  new result, free
  result.file = file
  let sz = img.getSize
  result.tex = img.newTexture
  
  if file =~ imageFilenamePattern:
    result.rect.width = matches[0].parseInt.cint
    result.rect.height = matches[1].parseInt.cint
  result.cols = int(sz.x / result.rect.width)
  result.rows = int(sz.y / result.rect.height)
  destroy img
  cache[file] = result



type
  AnimatedSprite = object
    t: PTilesheet
    index: int
    timer: float
    delay: float
    scale: TVector2f

AnimatedSprite.setInitializer do (e: PEntity):
  e[animatedsprite] = AnimatedSprite(timer: 1.0, delay: 1.0, index: 0)
  e[animatedsprite].scale = vec2f(1,1)

template withKey (J: PJsonNode; key: string; varname: expr; body:stmt): stmt {.immediate.}=
  if j.hasKey(key):
    let varname{.inject.}= j[key]
    block:
      body

msgImpl(AnimatedSprite, unserialize) do (j: PJsonNode):
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
    withKey(j, "scale", s):
      let s = s.toFloat
      sp.scale = vec2f(s,s)

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
  s.setScale entity[animatedsprite].scale
  R.draw s
  destroy s

type
  OneShotAnimation* = object
    t*: PTilesheet
    index*: int
    delay*: float
    timer*: float
    scale*: TVector2f

OneShotAnimation.setInitializer do (E: PEntity):
  let osa = e[oneshotanimation].addr
  osa.delay = 1.0
  osa.timer = osa.delay
  osa.scale = vec2f(1,1)

msgImpl(OneShotAnimation,unserialize) do (J: PJsonNOde):
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
    withKey(j, "scale", s):
      let s = s.toFloat
      sp.scale = vec2f(s,s)

msgImpl(OneShotAnimation,draw,9001) do (R: PRenderWindow):
  let s = entity[oneshotanimation].t.create(0, entity[oneshotanimation].index)
  s.setPosition entity.getPos.vec2f
  s.setRotation entity.getAngle.radToDeg
  s.setScale entity[oneshotanimation].scale
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

msgImpl(RollSprite, unserialize) do (J: PJsonNode):
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
    s: string

msgImpl(Named, unserialize) do (J: PJsonNode):
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
  Emitter* = object
    delay*: float
    cooldown*: float
    emits*: PJsonNode
    initialImpulse*: TVector2d
    inheritVelocity*: float
    mode*: EmitterMode
  EmitterMode* {.pure.}=enum
    auto, manual

msgImpl(Emitter,unserialize) do (J: PJsonNode):
  if j.hasKey("Emitter") and j["Emitter"].kind == jObject:
    let j = j["Emitter"]
    if j.hasKey("delay-ms"):
      entity[Emitter].delay = j["delay-ms"].num.int / 1000
    elif j.hasKey("delay"):
      entity[Emitter].delay.getFloat j,"delay", 0.250

    if j.hasKey"emits":
      entity[Emitter].emits = j["emits"]
    if j.hasKey"mode":
      if j["mode"].str == "manual":
        entity[Emitter].mode = EmitterMode.manual
      else:
        entity[Emitter].mode = EmitterMode.auto
    if j.hasKey"initial-impulse":
      entity[emitter].initialImpulse = vector2d(j["initial-impulse"])
    if j.hasKey"inherit-velocity":
      entity[emitter].inheritVelocity = j["inherit-velocity"].toFloat
# Emitter#update and #fire is in room.nim

type
  Position* = object
    p: TPoint2d
msgImpl(Position,setPos) do (p: TPoint2d):
  entity[position].p = p
msgImpl(Position,getPos) do -> TPoint2d:
  entity[position].p
msgImpl(Position,unserialize) do (J: PJsonNode):
  if j.hasKey("Position") and j["Position"].kind == jArray:
    entity[Position].p = point2d(j["Position"])
    echo entity[Position].p


type  
  Orientation* = object
    angle: float
msgImpl(Orientation,getAngle) do -> float:
  entity[Orientation].angle

msgIMpl(Orientation,unserialize)do(J:PJsonNode):
  if j.hasKey("Orientation"):
    entity[Orientation].angle = j["Orientation"].toFloat


import macros

template simpleComp(name): stmt {.immediate.} =
  type name * = object
    val: float
  msgImpl(name, unserialize) do (J: PJsonNode):
    if j.hasKey(astToStr(name)):
      entity[name].val = j[astToStr(name)].toFloat

simpleComp(AngularDampners)
msgImpl(AngularDampners, update) do (dt: float):
  if(;var (has,b) = entity.getBody; has):
    b.setAngVel b.getAngVel * entity[angularDampners].val


type Actuators* = object
  turnSpeed*: float
msgImpl(Actuators, unserialize) do (J:PJsonNode):
  if j.hasKey"Actuators":
    entity[actuators].turnSpeed = j["Actuators"].toFloat
msgImpl(Actuators,getTurnspeed) do -> float:
  return entity[actuators].turnspeed


type Thrusters* = object
  rvSpeed*, fwSpeed*:float
msgImpl(Thrusters,unserialize) do(J:PJsonNOde):
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
msgImpl(ZOrder, unserialize) do (J:PJsonNode):
  if j.hasKey"ZOrder":
    entity[ZOrder].z = j["ZOrder"].toInt

