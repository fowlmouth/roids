
import private/gsm, private/sfgui, 
  private/components, private/gamedat, private/room, private/room_interface,
  fowltek/entitty, private/debug_draw,
  csfml,csfml_colors, math, json
import chipmunk as cp
import basic2d except `$`

randomize()

proc distance*(a, b: TVector): float {.inline.} =
  return sqrt(pow(a.x - b.x, 2.0) + pow(a.y - b.y, 2.0))

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

proc unspec* (r: PRoomGS; ent: int) =
  r.player = TPlayer(mode: Playing, ent_id: ent)
proc spec* (r: PRoomGS) =
  r.player = TPlayer(mode: Spectator, watching: nothing[int]())

proc newRoomGS* (r: PRoom) : PGameState =
  let res = PRoomGS(room: r)
  res.spec
  
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
  #rcm.add u
  
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
        let id = gs.room.add_ent(ent)
        gs.unspec(id)
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
        else:
          echo "ents.len = ", ents.len
      of MouseLeft:
      
        var ent = gameData.newEnt(gameData.randomFromGroup("asteroids"))
        ent.setPos point2d(m.x.float, m.y.float)
        gs.room.addEnt ent
        
      else:
        discard
    else: discard
  of Playing:
    
    if evt.kind in {evtKeypressed, evtKeyreleased}:
      let 
        ic = gs.room.getEnt(gs.player.ent_id).get(InputController).addr
        kp = evt.kind == evtKeyPressed
      
      case evt.key.code
      of KeyLeft:
        ic.turnLeft = kp
      of keyRight:
        ic.turnRight = kp
      of keyUP:
        ic.frwd = kp
      of keyDOWN:
        ic.bckwd = kp
      else:
        nil

method update* (gs: PRoomGS; dt: float) =
  gs.gui.update dt
  if not gs.paused:
    gs.room.update dt

method draw * (w: PRenderWindow; gs: PRoomGS) =
  if gs.camera.isNil:
    gs.camera = w.getView.copy
  
  if gs.player.mode == Playing:
    gs.camera.setCenter vec2f(gs.room.getEnt(gs.player.ent_id).getPos)
  elif gs.player.watching:
    echo "watching ", gs.player.watching
    gs.camera.setCenter vec2f(gs.room.getEnt(gs.player.watching.val).getPos)
  
  w.setView gs.camera
  
  type PTy = ptr tuple[w: PRenderWindow; gs: PRoomGS]
  
  proc draw_shape (s: cp.pshape; data: PTy) {.cdecl.} =
    let eid = cast[int](s.getUserdata)
    if eid != 0:
      data.gs.room.getEnt(eid).draw data.w
  
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


