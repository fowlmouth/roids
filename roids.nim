
import gsm, sfgui, csfml,csfml_colors
import chipmunk as cp
import math,json

import basic2d except `$`

import components, gamedat, room
randomize()

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
  proc draw_shape (S: cp.PShape; data: PRenderWindow) {.cdecl.}=
    debugDraw(data, s)

  space.eachShape(cast[TSpaceShapeIteratorFunc](draw_shape), cast[pointer](w))

import fowltek/maybe_t
type
  PRoomGS* = ref object of PGameState
    room: PRoom
    debugDrawEnabled: bool
    gui: PWidget
    rcm: PWidget
    paused: bool
    addingImpulse: TMaybe[TVector2d]
    player: TPlayer
    camera: PView
  
  TPlayerMode = enum
    Spectator, Playing
  TPlayer* = object
    case mode: TPlayerMode
    of Playing:
      ent_id: int
    else:
      watching: TMaybe[int]


proc newRoomGS* (r: PRoom) : PGameState =
  let res = PRoomGS(room: r)
  
  res.player = TPlayer(mode: Spectator)
  
  var main_w = newCollection()
  
  res.gui = main_w
  
  return res

var g: PGod

proc removeRCM (gs: PRoomGS) =
  if not gs.rcm.isNil:
    gs.gui.PCollection.remove gs.rcm
    gs.rcm = nil
proc rightClickedOn* (gs: PRoomGS; x,y: float; ent_id: int) =
  var rcm = newUL()
  rcm.add(newTextWidget(gs.room.getEnt(ent_id).getName))
  rcm.add(newButton("destroy") do: 
    gs.room.destroyEnt(ent_id)
    gs.removeRCM
  )
  rcm.add(newButton("impulse") do:
    gs.addingImpulse = just(vector2d(x,y))
  )
  var u: PUpdateable
  u = newUpdateable(newTextWidget("velocity" )) do:
    u.w.PTextWidget.setText("Vel "& $gs.room.getEnt(ent_id).getVel )
  rcm.add u
  
  rcm.setPos x,y
  gs.removeRCM
  gs.rcm = rcm
  gs.gui.PCollection.add rcm

proc `()`(key: string; n: PJsonNode): PJsonNode {.delegator.}= n[key]
proc toggle* (switch: var bool){.inline.}=switch = not switch

method handleEvent* (gs: PRoomGS; evt: var TEvent) =
  if gs.gui.dispatch(evt):
    return

  case gs.player.mode
  of Spectator:
    case evt.kind
    of evtKeyPressed:
      const cameraSpeed = 4
      
      case evt.key.code
      of KeyRight:
        gs.camera.move vec2f(cameraSpeed, 0)
      of KeyLeft:
        gs.camera.move vec2f(-cameraSpeed, 0)
      of KeyUP:
        gs.camera.move vec2f(0,-cameraSpeed)
      of keyDOWN:
        gs.camera.move vec2f(0,cameraSpeed)
      
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
            if s.getSensor: return
            
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
    else: discard
  of Playing:
    nil
  

method update* (gs: PRoomGS; dt: float) =
  gs.gui.update dt
  if not gs.paused:
    gs.room.update dt

method draw * (w: PRenderWindow; gs: PRoomGS) =
  type PTy = ptr tuple[w: PRenderWindow; gs: PRoomGS]
  
  proc draw_shape (s: cp.pshape; data: PTy) {.cdecl.} =
    let eid = cast[int](s.getUserdata)
    if eid != 0:
      data.gs.room.getEnt(eid).draw data.w
  
  if gs.camera.isNil:
    gs.camera = w.getView.copy
  w.setView gs.camera
  
  var data = (w: w, gs: gs)
  gs.room.space.eachShape(
    cast[TSpaceShapeIteratorFunc](draw_shape), 
    data.addr)
  
  if gs.debugDrawEnabled:
    w.debugDraw gs.room.space

  w.setView w.getDefaultView
  w.draw gs.gui

gamedata = loadGamedata()

g = newGod(videoMOde(800,600,32),"roids")
g.replace newRoomGS(newRoom(gameData.j.rooms.duel1))
g.run


