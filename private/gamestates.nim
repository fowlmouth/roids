import 
  private/gsm, private/sfgui, private/room,private/room_interface,
  private/components, private/gamedat, private/debug_draw,
  private/player_data,
  fowltek/maybe_t, fowltek/entitty,
  json
import basic2d except `$`
import chipmunk as cp

# global game state manager
var g*: PGod

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
    dat: PPlayerData

  PPlayerData* = ref object
    name*: string
    controller: TControlSet

  TEvtResponder = proc (evt: var TEvent; active: var bool): bool
  TControlSet* = object
    forward, backward, turnright, turnleft, fireemitter: TEvtResponder

proc getResponder (j: PJsonNode): TEvtResponder =
  result = proc(evt: var TEvent; active: var bool):bool = false
  
  case j[0].str
  of "key":
    let k = parseEnum[TKeyCode]("key"& j[1].str)
    result = proc(evt: var TEvent;active: var bool):bool =
      if evt.kind in {evtKeyPressed,evtKeyReleased} and evt.key.code == k:
        result = true
        active = evt.kind == evtKeyPressed

proc loadPlayer* (f: string): PPlayerData =
  result = PPlayerData(name: "nameless sob")
  let j = json.parseFile(f)
  if j.hasKey"name":
    result.name = j["name"].str

  let controls = j["control-schemes"][j["controls"].str]
  template sc (c): stmt =
    result.controller.c = getResponder(controls[astToStr(c)])
  sc forward
  sc backward
  sc turnright
  sc turnleft
  sc fireemitter 


proc `()` (key: string; n: PJsonNode): PJsonNode {.delegator.}= n[key]

proc unspec* (r: PRoomGS; ent: int) =
  r.player = TPlayer(dat: r.player.dat, mode: Playing, ent_id: ent)
proc spec* (r: PRoomGS) =
  r.player = TPlayer(dat: r.player.dat, mode: Spectator, watching: nothing[int]())

proc newRoomGS* (r: PRoom; playerDat = loadPlayer("player.json")) : PGameState =
  let res = PRoomGS(room: r)
  res.player.dat = playerDat
  res.spec
  
  var main_w = newCollection()
  
  res.gui = main_w
  
  return res

proc removeRCM (gs: PRoomGS) =
  if not gs.rcm.isNil:
    gs.gui.PCollection.remove gs.rcm
    gs.rcm = nil
proc rightClickedOn* (gs: PRoomGS; p: TVector2i; ent_id: int) =
  var rcm = newUL()
  rcm.add(newTextWidget(gs.room.getEnt(ent_id).getName))
  rcm.add(newButton("destroy") do: 
    gs.room.destroyEnt(ent_id)
    gs.removeRCM
  )
  rcm.add(newButton("impulse") do:
    gs.addingImpulse = just(vector2d(p.x.float, p.y.float))
  )
  if gs.player.mode == Spectator:
    rcm.add(newButton("spectate") do:
      gs.player.watching = just(ent_id)
    )
  var u: PUpdateable
  u = newUpdateable(newTextWidget("velocity" )) do:
    u.w.PTextWidget.setText("Vel "& $gs.room.getEnt(ent_id).getVel )
  rcm.add u
  
  rcm.setPos p.x.float,p.y.float
  gs.removeRCM
  gs.rcm = rcm
  gs.gui.PCollection.add rcm

method handleEvent* (gs: PRoomGS; evt: var TEvent) =
  if gs.gui.dispatch(evt):
    return

  case gs.player.mode
  of Spectator:
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
        let id = gs.room.add_ent(ent)
        gs.unspec(id)
      else:
        nil
    
    of evtMouseButtonPressed:
      let m = TVector2i(x:evt.mouseButton.x, y:evt.mouseButton.y)
      let world_m = g.window.convertCoords(m, gs.camera)
      
      case evt.mouseBUtton.button
      of MouseRight:
        
        var ents:seq[int] = @[]
        gs.room.space.pointQuery(
          vector(world_m.x, world_m.y), 1, 0,
          (proc(s: cp.PShape, data: pointer){.cdecl.} =
            if s.getSensor: return
            
            let eid = cast[int](s.data)
            if eid > 0:
              cast[var seq[int]](data).add eid),
          ents.addr
        )
        IF ents.len == 1:
          gs.rightClickedOn(m, ents[0])

      of MouseLeft:

        var ent = gameData.newEnt(gameData.randomFromGroup("asteroids"))
        ent.setPos point2d(world_m.x.float, world_m.y.float)
        gs.room.addEnt ent
        
      else:
        discard
    else: discard
  of Playing:
    # see if evt is handled by responders for controller
    let 
      c = gs.player.dat.controller.addr
      ic = gs.room.getEnt(gs.player.ent_id)[InputController].addr
    
    template chkInput(x): stmt =
      if c.x(evt, ic.x): return
    chkInput(forward)
    chkInput(backward)
    chkInput(turnright)
    chkInput(turnleft)
    chkInput(fireemitter)
    discard """
    if gs.room.player.dat.controller.forward(evt)
    
    if evt.kind in {evtKeypressed, evtKeyreleased} and gs.room.getEnt(gs.player.ent_id).hasComponent(InputController):
      let 
        ic = gs.room.getEnt(gs.player.ent_id)[InputController].addr
        kp = evt.kind == evtKeyPressed
      
      case evt.key.code
      of KeyLeft:
        ic.turnLeft = kp
      of keyRight:
        ic.turnRight = kp
      of keyUP:
        ic.forward = kp
      of keyDOWN:
        ic.backward= kp
      of keyLControl:
        ic.fireemitter = kp
      else:
        nil
   """

method update* (gs: PRoomGS; dt: float) =
  if not gs.paused:
    if gs.player.mode == Spectator:
      const cameraSpeed = 16
      if is_keyPressed(keyRight):
        gs.camera.move vec2f(cameraSpeed, 0)
      elif is_keyPressed(KeyLeft):
        gs.camera.move vec2f(-cameraSpeed, 0)
      if is_keyPressed(KeyUP):
        gs.camera.move vec2f(0,-cameraSpeed)
      elif is_keyPressed(keyDOWN):
        gs.camera.move vec2f(0,cameraSpeed)

    gs.room.update dt

  gs.gui.update dt

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
