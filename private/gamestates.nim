import 
  private/gsm, private/room,private/room_interface,
  private/components, private/gamedat, private/debug_draw,
  private/player_data,
  fowltek/maybe_t, fowltek/entitty, fowltek/boundingbox, 
  private/sfgui2,
  json, csfml_colors,csfml
import basic2d except `$`
import chipmunk as cp

# global game state manager
var g*: PGod

import private/pause_state

type
  PRoomGS* = ref object of PGameState
    room: PRoom
    debugDrawEnabled: bool
    gui, rcm, skillMenu: sfgui2.PWidget
    
    addingImpulse: TMaybe[TVector2d]
    player: TPlayer
    camera: PView
  
  TPlayerMode = enum
    Spectator, Playing
  TPlayer* = object
    case mode: TPlayerMode
    of Playing:
      ent_id: int
    of Spectator:
      watching: TMaybe[int]
      input: InputController
    dat: PPlayerData

  PPlayerData* = ref object
    name*: string
    controller: TControlSet

  TEvtResponder = proc (evt: var TEvent; active: var bool): bool
  TControlSet* = object
    forward, backward, turnright, turnleft, fireemitter, spec: TEvtResponder
    skillmenu: TEvtResponder

proc getResponder (j: PJsonNode): TEvtResponder =
  result = proc(evt: var TEvent; active: var bool):bool = false

  template handleEVT (body:stmt):stmt {.immediate.}= 
    result = proc(evt: var TEvent; active: var bool): bool =
      body
    return

  case j[0].str
  of "key":
    let k_name = j[1].str
    let k = parseEnum[csfml.TKeyCode]("key"& k_name)
    handleEVT:
      if evt.kind in {evtKeyPressed,evtKeyReleased} and evt.key.code == k:
        result = true
        active = evt.kind == evtKeyPressed
  of "mouse-button":
    let b_name = j[1].str
    let b = parseEnum[csfml.TMouseButton]("button"& b_name)
    handleEVT:
      if  evt.kind in {evtMouseButtonPressed,evtMousebuttonreleased} and 
          evt.mousebutton.button == b:
        result = true
        active = evt.kind == evtMouseButtonPressed

proc loadPlayer* (f: string): PPlayerData =
  result = PPlayerData(name: "nameless sob")
  let j = json.parseFile(f)
  if j.hasKey"name":
    result.name = j["name"].str

  let controls = j["control-schemes"][j["controls"].str]
  template sc (c): stmt =
    # result.controller.forward = getResponder(controls["forward"])
    result.controller.c = getResponder(controls[astToStr(c)])
  sc forward
  sc backward
  sc turnright
  sc turnleft
  sc fireemitter 
  sc spec
  sc skillmenu


proc `()` (key: string; n: PJsonNode): PJsonNode {.delegator.}= n[key]

proc resetCamera* (gs: PRoomGS)=
  if not gs.camera.isNil:
    gs.camera.destroy
  gs.camera = g.window.getDefaultView.copy
  let sz = g.window.getSize
  gs.camera.setSize vec2f( sz.x, sz.y )

proc isSpec* (p: TPlayer): bool = p.mode == Spectator
proc unspec* (r: PRoomGS; ent: int) =
  r.player = TPlayer(dat: r.player.dat, mode: Playing, ent_id: ent)
  r.resetCamera
proc spec* (r: PRoomGS) =
  r.player = TPlayer(dat: r.player.dat, mode: Spectator, watching: nothing[int]())

proc pause* (r: PRoomGS) =
  g.push newPauseGS()

proc free* (r: PRoomGS) = 
  echo "free'd roomgs"

proc newRoomGS* (r: PJsonNode; playerDat = loadPlayer("player.json")): PGameState =
  var res: PRoomGS
  new res, free
  res.room = newRoom(r)
  res.player.dat = playerDat
  res.spec
  
  res.resetCamera
  if r.hasKey("start-camera"):
    res.camera.setCenter vec2f(r["start-camera"].point2d)

  var skm = hideable( newUL(), false )
  if r.hasKey"playable":
    for p in r["playable"]:
      let b = button(p.str) do:
        res.unspec(res.room.addEnt(gameData.newEnt(p.str)))
      skm.sons[0].add b
  skm.setPos point2d(100,100)
  
  let main_gui = newWidget()
  main_gui.add skm
  
  let pauseMenu = hideable(newUL(), false)
  
  let roomMenu = newUL()
  for name, r in gamedata.j["rooms"]:
    roomMenu.add(button(name) do:
      g.replace(newRoomGS(r))
    )
  
  pauseMenu.child.add(button("goto room") do:
    main_gui.add roomMenu
    pauseMenu.visible = false
  )
  pauseMenu.setPos point2d(200,100)
  
  main_gui.add pauseMenu
  
  res.gui = main_gui
  res.skillmenu = skm
  
  return res

proc removeRCM (gs: PRoomGS) =
  if not gs.rcm.isNil:
    gs.gui.remove gs.rcm

proc makeRightClickMenu (gs: PRoomGS; ent_id: int) =
  let result = newUL()
  template hideRCM: stmt = 
    gs.removeRCM
  
  result.add onclick(textWidget(gs.room.getEnt(ent_id).getName)) do:
    hideRCM
  result.add button("destroy") do:
    gs.room.doom(ent_id) #destroyEnt(ent_id)
    hideRCM
  
  if gs.player.mode == Spectator:
    result.add button("spectate") do:
      gs.player.watching = just(ent_id)
      hideRCM
  
  result.setPos point2d(g.window.getMousePosition)#gs.room.getEnt(ent_id).getPos

  gs.removeRCM
  gs.rcm = result
  gs.gui.add gs.rcm

proc makeInfoWindow (gs: PRoomGS; ent: int) =
  template rmIW: stmt = gs.gui.remove(iw)
  let iw = newUL()
  iw.add(button(gs.room.getEnt(ent).getName) do:
    rmIW
  )

proc checkInput* (c: TControlSet; ic: ptr InputController; evt: var TEvent): bool =
  template chkInput(x): stmt =
    when compiles(ic.x):
      when compiles(c.x(evt,ic.x)):
        if c.x(evt, ic.x): return true
      else:
        static:
          echo "Warning: input ", astToStr(x), " is not covered in TControlSet"
    else:
      static:
        echo "Warning: input ", astToStr(x), " is not covered in InputController"
  chkInput(spec)
  chkInput(skillmenu)
  chkInput(forward)
  chkInput(backward)
  chkInput(turnright)
  chkInput(turnleft)
  chkInput(fireemitter)

method handleEvent* (gs: PRoomGS; evt: var TEvent) =
  if gs.gui.dispatch(evt):
    return

  if evt.kind == evtResized:
    gs.camera.setSize vec2f( evt.size.width, evt.size.height )
    return
  # see if evt is handled by responders for controller
  let 
    ic =
      if gs.player.isSpec: gs.player.input.addr
      else: gs.room.getEnt(gs.player.ent_id)[InputController].addr
  if gs.player.dat.controller.checkInput(ic, evt):
    return

  if gs.player.isSpec:
    case evt.kind
    of evtKeyPressed:
      case evt.key.code
      
      of key_P:
        gs.pause
      of key_R:
        gamedata = load_game_data()
        g.replace newRoomGS(gamedata.j.rooms[gamedata.j["first-room"].str])
      of key_D:
        gs.debugDrawEnabled = not gs.debugDrawEnabled
      of key_F12:
        var ent = gameData.newEnt("hornet")
        ent.setPos point2d(100,100)
        let id = gs.room.add_ent(ent)
        gs.unspec(id)
      else:
        nil
    
    of evtMouseWheelMOved:
      let d = evt.mouseWheel.delta
      # down is -1
      # up is 1
      if d > 0:
        gs.camera.zoom 0.9
      else:
        gs.camera.zoom 1.1

    of evtMouseButtonPressed:
      let m = TVector2i(x:evt.mouseButton.x, y:evt.mouseButton.y)
      let world_m = g.window.convertCoords(m, gs.camera)
      
      case evt.mouseBUtton.button
      of MouseRight:
        
        var ents:seq[int] = @[]
        gs.room.physSys.space.pointQuery(
          vector(world_m.x, world_m.y), 1, 0,
          (proc(s: cp.PShape, data: pointer){.cdecl.} =
            if s.getSensor: return
            
            let eid = cast[int](s.data)
            if eid > 0:
              cast[var seq[int]](data).add eid),
          ents.addr
        )
        IF ents.len == 1:
          gs.makeRightClickMenu ents[0]

      of MouseLeft:

        var ent = gameData.newEnt(gameData.randomFromGroup("asteroids"))
        ent.setPos point2d(world_m.x.float, world_m.y.float)
        gs.room.addEnt ent
        
      else:
        discard
    else: discard

method update* (gs: PRoomGS; dt: float) =
  if gs.player.isSpec:
    if gs.player.input.skillmenu:
      gs.skillmenu.WidgetHideable.visible = true
      
    elif not gs.camera.isNil:
      const cameraSpeed = 16
      var offs: TVector2f
      if gs.player.input.turnRight:
        offs.x += cameraSpeed
      elif gs.player.input.turnLeft:
        offs.x -= cameraSpeed
      if gs.player.input.forward:
        offs.y -= cameraSpeed
      elif gs.player.input.backward:
        offs.y += cameraSpeed
      gs.camera.move offs
  else:
    if gs.room.getEnt(gs.player.ent_id)[InputController].spec:
      gs.spec
      
  gs.room.update dt

  #gs.gui.update dt

method draw * (w: PRenderWindow; gs: PRoomGS) =
  
  if gs.player.mode == Playing:
    gs.camera.setCenter vec2f(gs.room.getEnt(gs.player.ent_id).getPos)
  elif gs.player.watching:
    gs.camera.setCenter vec2f(gs.room.getEnt(gs.player.watching.val).getPos)
  
  w.setView gs.camera

  let viewSZ = gs.camera.getSize
  let viewPos = gs.camera.getCenter
  let rect = bb(
    viewPos.x - (viewSZ.x / 2),
    viewPos.y - (viewSZ.y / 2),
    viewSZ.x,
    viewSZ.y
  )
  gs.room.draw(rect, w)

  if gs.debugDrawEnabled:
    w.debugDraw gs.room.physsys.space

  w.setView w.getDefaultView

  gs.gui.draw w
