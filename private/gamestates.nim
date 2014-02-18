import 
  private/gsm, private/room,private/room_interface,
  private/components, private/gamedat, private/debug_draw,
  fowltek/maybe_t, fowltek/entitty, fowltek/boundingbox, fowltek/bbtree, 
  private/sfgui2, private/common,
  json, csfml_colors,csfml, logging
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
    playerListMenu: sfgui2.PWidget
    pauseMenu: WidgetHideable
    
    addingImpulse: TMaybe[TVector2d]
    player: TPlayer
    player_id: int # id of player (given when joining a room, this entity controls others like vehicles)
    player_dat: PPlayerData
    camera: PView
    
    radar_texture: PRenderTexture
  
  TPlayerMode = enum
    Spectator, Playing
  TPlayer* = object
    case mode: TPlayerMode
    of Playing:
      vehicle: int
    of Spectator:
      watching: TMaybe[int]
      input: InputController

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
proc unspec (r: PRoomGS; vehicle: int) =
  reset r.player
  r.player.mode = Playing
  r.player.vehicle = vehicle
  r.resetCamera

proc spec (r: PRoomGS) =
  reset r.player
  r.player.mode = Spectator

proc pause* (r: PRoomGS) =
  #g.push newPauseGS()
  r.pauseMenu.visible = true

proc free* (r: PRoomGS) = 
  echo "free'd roomgs"

proc initGui (gs: PRoomGS; r: PJsonNode)

proc newRoomGS* (room: string; playerDat = loadPlayer("player.json")): PGameState =
  echo "opening ", room
  
  let r = gameData.rooms[room]
  var res: PRoomGS
  new res, free
  res.room = newRoom(r)
  res.player_id = res.room.joinPlayer(playerDat.name)
  res.player_dat = playerDat
  res.spec
  
  res.resetCamera
  if r.hasKey("start-camera"):
    res.camera.setCenter vec2f(r["start-camera"].point2d)

  res.initGui r
  
  return res

proc playerVehicle* (gs: PRoomGS): PEntity =
  assert( not gs.player.isSpec )
  return gs.room.getEnt(gs.player.vehicle)
proc playerEntity* (gs: PRoomGS): PEntity =
  return gs.room.getEnt(gs.player_id)

proc hasOneOfTheseComponents* (entity:PEntity; components: varargs[int,`componentID`]):bool =
  for c in components:
    if not entity.typeinfo.all_components[c].isNil:
      return true

type RadarWidget = ref object of PWidget
  pos: TPoint2d
  sprite: PSprite
  room: PRoomGS

var radarWidgetVT = sfgui2.defaultVT
radarWidgetVT.draw = proc(g:PWidget; w:PRenderWindow) =
  let g = g.radarWidget
  if g.room.radarTexture.isNil: 
    return
  
  if g.sprite.isNil:
    g.sprite = newSprite()
    g.sprite.setTexture g.room.radarTexture.getTexture, true
  
  g.sprite.setPosition vec2f(g.pos)
  w.draw g.sprite

radarWidgetVT.setPos = proc(G:PWidget; P:TPoint2d) =
  g.radarWidget.pos = p



proc newRadarWidget (R: PRoomGS): RadarWidget =
  result = RadarWidget(room: R, vtable: radarWidgetVT.addr)
  result.init

type T_IFF*{.pure.} = enum Inert,Foe,Friend 
proc IFF (room: PRoom; player1, player2: int): TIFF =
  template p1 : expr = room.getEnt(player1)
  template p2 : expr = room.getEnt(player2)
  if p2.hasComponent(Owned) and p2[Owned].by == player1:
    return TIFF.Friend
  if p1.hasComponent(TeamMember):
    if p2.hasComponent(TeamMember):
      if p1[teamMember].team == p2[teamMember].team:
        return TIFF.friend
      else:
        return TIFF.foe
  
  if not p2.hasOneOfTheseComponents(Thrusters, Actuators):
    return TIFF.Inert
  
  return TIFF.Foe
proc color (iff: TIFF): csfml.TColor =
  case iff
  of TIFF.Friend: green
  of TIFF.Foe: red
  of TIFF.Inert: white
proc updatePlayerRadar (gs: PRoomGS) =
  if not(gs.player.isSpec) or not gs.playerEntity.hasComponent(Radar):
    return

  let r = gs.playerVehicle[Radar].r
  if gs.radarTexture.isNil:
    gs.radarTexture = newRenderTexture(r.cint, r.cint, false)

  if not(gs.radarTexture.setActive (true)):
    warn "Could not activate radar texture"
    return
    
  gs.radarTexture.clear white
  let view = newView()
  view.setSize vec2f(r, r)
  view.setCenter vec2f(gs.playerVehicle.getPos)
  gs.radarTexture.setView view
  let bb = bb(r - (r/2), r - (r/2), r, r)
  var pointVA{.global.} = newVertexArray(csfml.Points, 1)
  proc tree_q (entity:int) = 
    let status = iff(gs.room, gs.player_id, entity)
    pointVA[0].position = vec2f(gs.room.getEnt(entity).getPos)
    pointVA[1].color = status.color
    gs.radarTexture.draw pointVA
  gs.room.renderSys.tree.query(bb, tree_q)
  gs.radarTexture.display
  discard gs.radarTexture.setActive(false)
  gs.radarTexture.setView nil.PView
  destroy view

proc buildPlayerlist (gs: PRoomGS)
proc buildPlayerGUI (GS:PRoomGS) =
  gs.buildPlayerList
  if not gs.player.isSpec:
    gs.updatePlayerRadar


proc requestUnspec ( gs: PRoomGS; vehicle: string) =
  var(has, ent_id) = gs.room.requestUnspec(gs.player_id, vehicle)
  if has:
    gs.unspec(ent_id)
    gs.buildPlayerGUI


proc buildPlayerlist (gs: PRoomGS) =
  # team/player menu
  
  if not gs.playerListMenu.isNil:
    gs.gui.remove gs.playerListMenu
  
  let playerList = hideable(newUL(), true)
  
  for team in gs.room.teamSys.teams:
    
    if team.members.len > 0:
      # has players
      var section = newUL()
      section.add(textWidget(team.name))
      
      for ent_id in team.members:
        section.add(textWidget(gs.room.getEnt(ent_id).getName))
      
      playerList.child.add section

  let playerListMenu = newUL()
  playerListMenu.add(button("Playerlist [Hide]") do:
    playerListMenu.sons[1].WidgetHideable.visible.toggle
  )
  playerListMenu.add playerList
  
  playerListMenu.setPos point2d( 500,5 )
  let pos = point2d(g.window.getSize.x.float - playerListMenu.getBB.width, 5)
  playerListMenu.setPos pos
  
  gs.playerListMenu = playerListMenu
  gs.gui.add gs.playerListMenu

proc initGui (gs: PRoomGS; r: PJsonNode) =

  let main_gui = newWidget()
  
  #skill menu
  var skm = hideable( newUL(), false )
  if r.hasKey"playable":
    for p in r["playable"]:
      let name = p.str
      let b = button(name) do:
        gs.requestUnspec(name)
        #gs.unspec(gs.room.addEnt(gameData.newEnt(p.str)))
        skm.visible = false
      skm.child.add b
  skm.setPos point2d(100,100)
  
  #choose room menu
  let roomMenu = newUL()
  for name, data in gamedata.rooms:
    let n = name
    let b = button(n) do:
      echo "Switching to ", n
      g.replace(newRoomGS(n))
    roomMenu.add b
  
  #pause menu
  let pauseMenu = hideable(newUL(), false)
  pauseMenu.child.add(button("goto room") do:
    main_gui.add roomMenu
    pauseMenu.visible = false
  )
  
  pauseMenu.setPos point2d(200,100)
  roomMenu.setPos point2d(200,100)
  
  main_gui.add skm
  main_gui.add pauseMenu
  main_gui.add newRadarWidget(gs)
  
  gs.gui = main_gui
  gs.skillmenu = skm
  gs.pauseMenu = pauseMenu
  
  gs.buildplayerlist


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
        if c.x(evt, ic.x): 
          return true
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

proc playerInputController(gs: PRoomGS): ptr InputController =
  if gs.player.isSpec: gs.player.input.addr
  else: gs.room.getEnt(gs.player.vehicle)[InputController].addr

method handleEvent* (gs: PRoomGS; evt: var TEvent) =
  if gs.gui.dispatch(evt):
    return

  if evt.kind == evtResized:
    gs.camera.setSize vec2f( evt.size.width, evt.size.height )
    return
  # see if evt is handled by responders for controller
  let ic = gs.playerInputController
  if gs.player_dat.controller.checkInput(ic, evt):
    return

  if gs.player.isSpec:
    case evt.kind
    of evtKeyPressed:
      case evt.key.code
      
      of key_P,key_escape:
        gs.pause
      of key_R:
        gamedata = load_game_data(gamedata.dir)
        g.replace newRoomGS(gs.room.name)
      of key_D:
        gs.debugDrawEnabled = not gs.debugDrawEnabled
      of key_F12:
        discard """ var ent = gameData.newEnt("hornet")
        ent.setPos point2d(100,100)
        let id = gs.room.add_ent(ent)
        gs.unspec(id) """
        gs.requestUnspec("hornet")
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

        var ent = gameData.newEnt(gs.room, gameData.randomFromGroup("asteroids"))
        ent.setPos point2d(world_m.x.float, world_m.y.float)
        gs.room.addEnt ent
        
      else:
        discard
    else: discard

method update* (gs: PRoomGS; dt: float) =
  let ic = gs.playerInputController
  if gs.player.isSpec:
    if ic.skillmenu:
      gs.skillmenu.WidgetHideable.visible = true
      
    elif not gs.camera.isNil:
      const cameraSpeed = 16
      var offs: TVector2f
      if ic.turnRight:
        offs.x += cameraSpeed
      elif ic.turnLeft:
        offs.x -= cameraSpeed
      if ic.forward:
        offs.y -= cameraSpeed
      elif ic.backward:
        offs.y += cameraSpeed
      gs.camera.move offs

  else:
    if ic.spec:
      gs.spec

  gs.room.update dt

  #gs.gui.update dt

method draw * (w: PRenderWindow; gs: PRoomGS) =
  
  if gs.player.mode == Playing:
    gs.camera.setCenter vec2f(gs.room.getEnt(gs.player.vehicle).getPos)
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
    w.debugDraw gs.room 

  w.setView w.getDefaultView

  gs.gui.draw w
