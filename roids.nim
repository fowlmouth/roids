
import gsm, sfgui, csfml,csfml_colors
import chipmunk as cp
import basic2d,math,json, fowltek/maybe_t
randomize()


import strutils
proc ff* (f: float; prec = 2): string = formatFloat(f, ffDecimal, prec)

# the penalty for having sfml vectors and chipmunk vectors
proc vector* [T: TNumber] (x, y: T): TVector = 
  result.x = x.cpfloat
  result.y = y.cpfloat
proc vector* (v: TVector2d): TVector =
  result.x = v.x
  result.y = v.y
proc vec2f* (v: TVector): TVector2f = TVector2f(x: v.x, y: v.y)
proc vec2f* (v: TPoint2d): TVector2f = TVector2f(x: v.x, y: v.y)
proc vector2d* (v: TVector): TVector2d =
  result.x = v.x
  result.y = v.y
proc point2d* (v: TVector): TPoint2d =
  point2d(v.x, v.y)
proc point2d* (v: TVector2d): TPoint2d=
  point2d(v.x, v.y)

proc getFloat* (result: var float; j: PJsonNode; key: string, default = 0.0) =
  if j.kind == JObject and j.hasKey(key):
    case j[key].kind
    of jInt:
      result = j[key].num.float
    of jFloat:
      result = j[key].fnum.float
    else:
      echo "Not a float value: ", j[key]
      result = default
    
  else:
    when defined(Debug):
      echo "Missing float key ",key
    result = default
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
  of jArray:
    case n[0].str
    of "random":
      result = random(n[1].toFloat)
  else:
    echo "Not a float value: ", n

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

import fowltek/entitty,fowltek/idgen

proc addToSpace* (s: PSpace) {.multicast.}
proc removeFromSpace*(s: PSpace){.multicast.}

proc impulse* (f: TVector2d) {.unicast.}
proc setPos* (p: TPoint2d) {.unicast.}
proc getPos* : TPoint2d {.unicast.}
proc getAngle*: float {.unicast.}

proc update* (dt: float) {.multicast.}
proc draw* (R: PRenderWindow) {.unicast.}

proc unserialize* (j: PJsonNode) {.multicast.}

type
  Body* = object
    b: cp.PBody
    s: cp.PShape
Body.setDestructor do (E: PEntity):
  if not e[body].s.isNil:
    destroy e[body].s
  if not e[body].b.isNil:
    destroy e[body].b

msgImpl(Body, getAngle) do -> float:
  entity[body].b.getAngle.float

msgImpl(Body, unserialize) do (J: PJsonNode):
  if j.hasKey("Body"):
    let j = j["Body"]
    let mass = j["mass"].toFloat
    case j["shape"].str
    of "circle":
      var radius: float
      radius.getFloat j, "radius", 30.0
      let moment = momentForCircle(mass, radius, 0.0, vectorZero)
      let b = newBody(mass, moment)
      let shape = newCircleShape(b, radius, vectorZero)
      shape.setElasticity( 1.0 )

      entity[body].b = b
      entity[body].s = shape
    else:
      quit 0 

  if j.hasKey("initial-impulse"):
    var vec = j["initial-impulse"].vector2d
    entity.impulse vec
    

msgImpl(Body, setPos) do (p: TPoint2d):
  if not entity[body].b.isNil:
    entity[body].b.setPos vector(p.x, p.y)
msgImpl(Body, getPos) do -> TPoint2d:
  point2d(entity[body].b.p)

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


var collisionTypes = initTable[string, cuint](64)
var next = 1.cuint
proc ct* (s: string): cuint = 
  if not collisionTypes.hasKey(s):
    collisionTypes[s] = next
    next += 1
  return collisionTypes[s]

type
  Sensor* = object
    shape: cp.PShape
Sensor.requiresComponent Body

msgImpl(Sensor, unserialize) do (J: PJsonNode):
  if j.hasKey("Sensor"):
    let j = j["Sensor"]
    var radius: float
    radius.getFloat j, "radius", 500.0
    entity[sensor].shape = newCircleShape(entity[Body].b, radius, vectorZero)
    entity[sensor].shape.setSensor true
    
    if j.hasKey("collision-type"):
      entity[sensor].shape.setCollisionType(ct(j["collision-type"].str))

msgImpl(Sensor, addToSpace) do (S: PSpace):
  discard s.addShape( entity[sensor].shape)


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

AnimatedSprite.setInitializer do (e: PEntity):
  e[animatedsprite] = AnimatedSprite(timer: 1.0, delay: 1.0, index: 0)

msgImpl(AnimatedSprite, unserialize) do (j: PJsonNode):
  if j.hasKey("AnimatedSprite"):
    let j = j["AnimatedSprite"]
    let sp = entity[animatedsprite].addr
    sp.t = tilesheet(j["file"].str)
    sp.index = 0
    sp.delay.getFloat j, "delay", 1.0
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
  R.draw s
  destroy s

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
    col = int( ( (rs.roll + 1.0) / 2.0) * rs.t.cols.float )
    row = int( (( entity.getAngle + DEG90 ) mod DEG360) / DEG360 * rs.t.rows.float )
  
  let 
    s = rs.t.create(row, col)
  s.setPosition entity.getPos.vec2f
  r.draw s
  destroy s

var 
  dom = newDomain()


type
  PRoom* = ref object
    space: PSpace
    ents: seq[TEntity]
    ent_id: TIDgen[int]
    activeEnts: seq[int]

type
  PGameData* = var TGameData
  TGameData * = object
    entities: TTable[string,TJent] # ent name => typeinfo and json data
    groups: TTable[string, seq[string]] # group name => @[ ent names ]
    j: PJsonNode 
  TJent = tuple[ ty: PTypeinfo, j: PJsonNode ]

proc randomFromGroup* (m: var TGameData; group: string): string =
  if m.groups.hasKey(group):
    let len = m.groups.mget(group).len
    return m.groups.mget(group)[random(len)]
    

proc loadGameData* (f = "ships.json"): TGameData =
  result.j = json.parseFile(f)
  result.entities = initTable[string,TJent](64) 
  result.groups = initTable[string,seq[string]](64)

  for name, x in result.j["entities"].pairs:
    var y: TJent
    var components: seq[int] = @[]
    for key, blah in x.pairs:
      try:
        let c = findComponent(key)
        components.add c
      except:
        discard
    y.ty = dom.getTypeinfo(components)
    y.j = x
    result.entities[name] = y
  for name, g in result.j["groups"].pairs:
    result.groups[name] = @[]
    for s in g:
      if result.entities.hasKey(s.str):
        result.groups.mget(name).add s.str


var gameData: TGameData

proc new_ent (d: PGameData; name: string): TEntity =
  when defined(debug):
    echo "instantiating " , name
  let tj = d.entities[name]
  result = tj.ty.newEntity
  result.unserialize tj.j

proc get_ent* (r: PRoom; id: int): PEntity = r.ents[id]
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

proc newRoom* (j: PJsonNode) : Proom =
  result.new free
  result.activeEnts = @[]
  result.ents = @[]
  result.ent_id = newIDgen[int]()
  discard result.ent_id.get # use up 0
  result.space = newSpace()
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
      pos: TPoint2d
    count.getInt obj, "count", 1
    pos.getPoint obj, "pos"
    
    if obj.hasKey("obj"):
      var ent = gameData.newEnt(obj["obj"].str)
      ent.setPos pos
      result.addEnt ent
      continue
    
    if obj.hasKey("group"):
      let g = obj["group"].str
      for i in 0 .. < count:
        var ent = gameData.newEnt(gameData.randomFromGroup(g))
        ent.setPos pos
        if obj.hasKey("extra-data"):
          ent.unserialize obj["extra-data"]
        result.addEnt ent
  
  #for i in 0 .. 50 :
  #  let pos = point2d( w / 2, h / 2 )
  #  result.add_asteroid pos
  

proc update* (r: PRoom; dt: float) =
  for id in r.activeEnts:
    r.ents[id].update dt
  r.space.step dt

proc distance*(a, b: TVector): float {.inline.} =
  return sqrt(pow(a.x - b.x, 2.0) + pow(a.y - b.y, 2.0))
proc debugDraw* (w: PRenderWindow; shape: cp.PShape) =
  case shape.klass.kind
  of cp_circle_shape:
    var c {.global.} = newCircleShape(1.0, 30)
    c.setPosition shape.getBody.p.vec2f
    let r = shape.getCircleRadius
    c.setRadius r
    c.setOrigin vec2f(r,r)
    var color = white
    if shape.getSensor:
      color.a = 30
      c.setOutlineThickness 1.0
    else:
      color.a = 70
      c.setOutlineThickness 0.0
    c.setFillColor(color)
    w.draw c
  of cp_segment_shape:
    var s {.global.} = newVertexArray(csfml.Lines, 2)
    s[0].position = shape.getSegmentA.vec2f
    s[1].position = shape.getSegmentB.vec2f
    w.draw s
  else:
    discard

proc debugDraw* (w: PRenderWindow; space: PSpace) =
  proc draw_shape (S: cp.PShape; data: pointer) {.cdecl.}=
    debugDraw(cast[PRenderWindow](data), s)
    
  space.eachShape(draw_shape, cast[pointer](w))
  

type
  PRoomGS* = ref object of PGameState
    room: PRoom
    debugDrawEnabled: bool
    gui: PWidget
    rcm: PWidget
    paused: bool
    addingImpulse: TMaybe[TVector2d]

proc newRoomGS* (r: PRoom) : PGameState =
  let res = PRoomGS(room: r)
  
  var main_w = newCollection()
  res.gui = main_w
  
  #res.room.addEnt newEnt("hornet")
  
  return res

var g: PGod

proc removeRCM (gs: PRoomGS) =
  if not gs.rcm.isNil:
    gs.gui.PCollection.remove gs.rcm
    gs.rcm = nil
proc rightClickedOn* (gs: PRoomGS; x,y: float; ent_id: int) =
  var rcm = newUL()
  rcm.add(newButton("destroy") do: 
    gs.room.destroyEnt(ent_id)
    gs.removeRCM
  )
  rcm.add(newButton("impulse") do:
    gs.addingImpulse = just(vector2d(x,y))
  )
  
  rcm.setPos x,y
  gs.removeRCM
  gs.rcm = rcm
  gs.gui.PCollection.add rcm

proc `()`(key: string; n: PJsonNode): PJsonNode {.delegator.}= n[key]
proc toggle* (switch: var bool){.inline.}=switch = not switch

method handleEvent* (gs: PRoomGS; evt: var TEvent) =
  if gs.gui.dispatch(evt):
    return

  case evt.kind
  of evtKeyPressed:
    case evt.key.code
    of key_P:
      gs.paused.toggle
    of key_R:
      gamedata = load_game_data()
      let r = newRoom(gamedata.j.rooms.duel1)
      g.replace newRoomGS(r)
    of key_D:
      gs.debugDrawEnabled = not gs.debugDrawEnabled
    of key_F12:
      var ent = gameData.newEnt("hornet")
      ent.setPos point2d(100,100)
      gs.room.add_ent ent
      
    else:
      nil
      
  of evtMouseButtonPressed:
    let m = (x:evt.mouseButton.x, y:evt.mouseButton.y)
    
    case evt.mouseBUtton.button
    of MouseRight:
      
      var ents:seq[int] = @[]
      gs.room.space.pointQuery(
        vector(m.x, m.y), 1, 0,
        (proc(s: cp.PShape, data: pointer){.cdecl.} =
          let eid = cast[int](s.data)
          if eid > 0:
            cast[var seq[int]](data).add eid),
        ents.addr
      )
      IF ents.len == 1:
        gs.rightClickedOn(m.x.float, m.y.float, ents[0])

    of MouseLeft:
    
      var ent = gameData.newEnt(gameData.randomFromGroup("asteroids"))
      ent.setPos point2d(m.x.float, m.y.float)
      gs.room.addEnt ent
      
    else:
      discard
  else:
    discard

method update* (gs: PRoomGS; dt: float) =
  if not gs.paused:
    gs.room.update dt

method draw * (w: PRenderWindow; gs: PRoomGS) =
  type PTy = ptr tuple[w: PRenderWindow; gs: PRoomGS]
  
  proc draw_shape (s: cp.pshape; data: PTy) {.cdecl.} =
    let eid = cast[int](s.getUserdata)
    if eid != 0:
      data.gs.room.ents[eid].draw data.w
  
  var data = (w: w, gs: gs)
  gs.room.space.eachShape(
    cast[TSpaceShapeIteratorFunc](draw_shape), 
    data.addr)
  
  if gs.debugDrawEnabled:
    w.debugDraw gs.room.space

  w.draw gs.gui

gamedata = loadGamedata()

g = newGod(videoMOde(800,600,32))
g.replace newRoomGS(newRoom(gameData.j.rooms.duel1))
g.run


