import 
  private/gsm, private/room,private/room_interface,
  private/components, private/gamedat, private/debug_draw,
  fowltek/maybe_t, fowltek/entitty, fowltek/boundingbox, fowltek/bbtree,
  fowltek/pointer_arithm, 
  private/sfgui2, private/common, private/color_gradient, 
  json, csfml_colors,csfml,csfml_audio, logging, os
import basic2d except `$`
import chipmunk as cp
when defined(useIRC):
  import irc
  from sockets import TPort
  type  TIRCServer = tuple[address:string,port:TPort,channels:seq[string]]
  proc `$` (some: TIRCServer): string = "irc://$1:$2".format( some.address, some.port.int16 ) 


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
    radar_timer: PClock
    
    vehicleGui: PWidget # vehicle-specific gui (inventory list, radar)
    
    when defined(useIRC):
      irc: PAsyncIRC
  
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
    fontSettings: TFontSettings
    when defined(useIRC):
      irc: TIRCServer

  TEvtResponder = proc (evt: var TEvent; active: var bool): bool
  TControlSet* = object
    forward, backward, turnright, turnleft, fireemitter, spec: TEvtResponder
    skillmenu, fireEmitter1: TEvtResponder

proc getResponder (j: PJsonNode; key: string): TEvtResponder =
  result = proc(evt: var TEvent; active: var bool):bool = false
  
  if not j.hasKey(key): return
  let j = j[key]

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
  new(result) do (P:PPlayerData):
    if p.fontSettings.font != defaultFontSettings.font:
      destroy p.fontSettings.font
  
  let j = json.parseFile(f)
  
  if j.hasKey"name":
    result.name = j["name"].str
  else:
    result.name = "nameless sob"
  
  # load font
  result.fontSettings = sfgui2.defaultFontSettings
  block:
    var f_json = j["gui-font"]["font"]
    var font = j["fonts"]
    for i in 0 .. < len(f_json):
      font = font[f_json[i].str]
    
    let f = newFont("assets/fonts" / font.str)
    if not f.isNil: result.fontsettings.font = f
    
    result.fontSettings.characterSize = j["gui-font"]["size"].toInt

  let controls = j["control-schemes"][j["controls"].str]
  template sc (c): stmt =
    # result.controller.forward = getResponder(controls["forward"])
    result.controller.c = getResponder(controls, astToStr(c))
  sc forward
  sc backward
  sc turnright
  sc turnleft
  sc fireemitter 
  sc spec
  sc skillmenu
  
  sc fireemitter1
  
  when defined(useIRC):
    if j.hasKey"irc-servers" and j.hasKey"irc":
      let srv = j["irc-servers"][j["irc"].str]
      result.irc.address = srv["address"].str
      result.irc.port = TPort(srv["port"].toInt)
      result.irc.channels = @[]
      if j.hasKey"channel":
        result.irc.channels.add j["channel"].str
      if j.hasKey"channels":
        for chan in j["channels"]:
          result.irc.channels.add chan.str
      if result.irc.channels.len == 0:
        result.irc.channels.add "#roids" 


proc `()` (key: string; n: PJsonNode): PJsonNode {.delegator.}= n[key]

proc resetCamera* (gs: PRoomGS)=
  if not gs.camera.isNil:
    gs.camera.destroy
  gs.camera = g.window.getDefaultView.copy
  let sz = g.window.getSize
  gs.camera.setSize vec2f( sz.x, sz.y )

proc updateVehicleGUI (GS:PROOMGS)

proc isSpec* (p: TPlayer): bool = p.mode == Spectator
proc unspec (r: PRoomGS; vehicle: int) =
  reset r.player
  r.player.mode = Playing
  r.player.vehicle = vehicle
  r.resetCamera
  r.updateVehicleGUI

proc playerVehicle* (gs: PRoomGS): PEntity =
  assert( not gs.player.isSpec )
  return gs.room.getEnt(gs.player.vehicle)
proc playerEntity* (gs: PRoomGS): PEntity =
  return gs.room.getEnt(gs.player_id)

proc playerPos* (gs: PRoomGS): TPoint2d =
  # returns the player's vehicle position or the players position
  if gs.player.isSpec: gs.playerEntity.getPos
  else: gs.playerVehicle.getPos


proc spec (r: PRoomGS) =
  if not(r.player.isSpec): 
    r.playerEntity.setPos r.playerVehicle.getPos
  reset r.player
  r.player.mode = Spectator

proc pause* (r: PRoomGS) =
  #g.push newPauseGS()
  r.pauseMenu.visible = true

proc free* (r: PRoomGS) = 
  echo "free'd roomgs"



proc initGui (gs: PRoomGS; r: PJsonNode)

proc newRoomGS* (room: string; playerDat = loadPlayer("player.json")): PGameState =
  info "Opening room $#", room
  
  let r = gameData.rooms[room]
  let room = newRoom(r)
  
  var res: PRoomGS
  new res, free
  res.room = room
  res.player_id = res.room.joinPlayer(playerDat.name)
  res.player_dat = playerDat
  res.spec
  
  res.resetCamera
  if r.hasKey("start-camera"):
    res.camera.setCenter vec2f(r["start-camera"].point2d)

  res.initGui r
  
  when defined(useIRC):
    res.irc = asyncIrc(
      res.player_dat.irc.address, 
      port = res.player_dat.irc.port, 
      nick = res.playerEntity.getName,
      user = "roids-client", 
      joinChans = res.player_dat.irc.channels,
      ircEvent = (proc (irc: PAsyncIRC; event: TIRCEvent) =
        case event.typ
        of evConnected: 
          echo "Connected."
        of evDisconnected: discard
        of evMsg:
          if event.cmd == mprivmsg:
            echo "<$1> $2".format(
              event.nick, 
              event.params[event.params.high]
            )
          else:
            warn "IRC $1 $2".format(event.cmd, event.raw)
      )
    )
    info "Connecting to $#", res.playerDat.irc
    res.irc.connect
  
  return res


proc hasOneOfTheseComponents* (entity:PEntity; components: varargs[int,`componentID`]):bool =
  for c in components:
    if not entity.typeinfo.all_components[c].isNil:
      return true


proc guiFontSettings (gs: PRoomGS): TFontSettings {.inline.} = gs.playerDat.fontSettings


type RadarWidget = ref object of PWidget
  pos: TPoint2d
  sprite: PSprite
  room: PRoomGS

var radarWidgetVT = sfgui2.defaultVT
radarWidgetVT.draw = proc(g:PWidget; w:PRenderWindow) =
  let g = g.radarWidget
  if g.room.radarTexture.isNil: 
    warn "Gamestate has no radarTexture"
    return
  
  if g.sprite.isNil:
    g.sprite = newSprite()
    g.sprite.setTexture g.room.radarTexture.getTexture, true
    g.sprite.setPosition vec2f(g.pos)
    g.sprite.setScale vec2f(1/4,1/4)

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
  if not gs.playerEntity.hasComponent(Radar):
    return

  let r = gs.playerEntity[Radar].r
  if gs.radarTexture.isNil:
    gs.radarTexture = newRenderTexture(r.cint, r.cint, false)

  if not(gs.radarTexture.setActive (true)):
    warn "Could not activate radar texture"
    return
  
  gs.radarTexture.clear black
  
  let view = newView()
  view.setSize vec2f(r, r)
  view.setCenter vec2f(gs.playerPos)
  gs.radarTexture.setView view
  let bb = bb(r.float - (r/2), r.float - (r/2), r.float, r.float)
  block:
    var borders{.global.}=newVertexArray(csfml.LinesStrip,1)
    debugDraw gs.radarTexture, bb, borders
    
  #var pointVA{.global.} = newVertexArray(csfml.Points, 1)
  var circ{.global.} = newCircleShape(1.0, 16)
  proc tree_q (entity:int) = 
    let status = iff(gs.room, gs.player_id, entity)
    let radius = gs.room.getEnt(entity).getRadius
    if radius.has and radius.val > 6: circ.setRadius radius.val
    else:          circ.setRadius 6.0
    circ.setFillColor status.color
    gs.radarTexture.draw circ
    
    #pointVA[0].position = vec2f(gs.room.getEnt(entity).getPos)
    #pointVA[1].color = status.color
    #gs.radarTexture.draw pointVA
    
  gs.room.renderSys.tree.query(bb, tree_q)
  gs.radarTexture.display
  discard gs.radarTexture.setActive(false)
  destroy view


type PRectWidget* = ref object of PWidget
  rect*: csfml.PRectangleShape
var rectWidgetVT = sfgui2.defaultVT
rectWidgetVT.draw = proc(G:PWidget; W:PRenderWIndow)=
  w.draw g.PRectWidget.rect
rectWidgetVT.setPos = proc(G:PWidget; P:tpoint2d)=
  g.prectwidget.rect.setposition p.vec2f
 
proc rectwidget (sz: TVector2d): PRectWidget =
  result = PRectWidget(rect: newRectangleShape(sz.vec2f))
  result.vtable = rectWidgetVT.addr
  result.init

var batteryColors: seq[TColor]
block:
  var gradient = initColorScale()
  gradient.insert 0.0, red
  gradient.insert 1.0, yellow
  gradient.insert 2.0, green
  batteryColors = gradient.toSeq(20)

proc batteryGaugeWidget (sz: TVector2d; gs: PRoomGS): PRectWidget =
  result = rectWidget(sz)
  result.rect.setFillColor green
  result.update_f = proc( G: PWIDGET ) =
    let g = G.PRectWidget
    let 
      nrg_pct = gs.playerVehicle.getEnergyPct
      color_idx = int( nrg_pct * (len(batteryColors) - 1).float )
    g.rect.setFillColor batteryColors[color_idx]
    g.rect.setSize vec2f(sz.x * nrg_pct , sz.y)
    g.rect.setOrigin g.rect.getSize / 2

proc emitterSlotWidget ( GS:PROOMGS; ESLOT:INT ): WidgetText =
  result = textWidget("|||", gs.guiFontSettings)
  result.updateF = proc( G:PWIDGET ) = 
    var text = gs.playerVehicle[emitters].ems[e_slot].e.name
    var color = green 
    if gs.playerVehicle[emitters].ems[e_slot].cooldown > 0:
      text.add " "
      text.add ff(gs.playerVehicle[emitters].ems[e_slot].cooldown, 4)
      text.add 's'
      color = red
    g.WidgetText.text.setString text
    g.WidgetText.text.setColor color
    

proc updateVehicleGUI (gs: PRoomGS) =
  if not gs.VehicleGUI.isNIL:
    gs.gui.remove gs.VehicleGUI
  gs.VehicleGUI = newWidget()
  gs.gui.add gs.vehicleGUI
  
  gs.updatePlayerRadar
  
  
  # build player's emitters widget
  let v_id = gs.playerVehicle.id
  
  if gs.playerVehicle.hasComponent(Emitters):
    
    var ew = newUL()
    
    for e_slot in 0 .. < len(gs.playerVehicle[emitters].ems):
      ew.add emitterSlotWidget(gs, e_slot)
    
    ew.setPos point2d(0,0)
    ew.setPos point2d(3, g.window.getSize.y / 2)
    
    gs.VehicleGUI.add ew
  
  if gs.playervehicle.hasComponent(Battery):

    let 
      size = vector2d( 500, 15 )
      batteryGauge = batteryGaugeWidget(size, gs) 
      midScreen = vector2d( g.window.getSize.x / 2, g.window.getSize.y.float - 15 - 10 )
    batteryGauge.setPos midScreen.point2d
    
    gs.VehicleGUI.add batteryGauge


proc buildPlayerlist (gs: PRoomGS)
proc buildPlayerGUI (GS:PRoomGS) =
  gs.buildPlayerList
  if not gs.player.isSpec:
    gs.updateVehicleGUI

proc playerTeam ( GS:PROOMGS ): TMaybe[PTeam] =
  if gs.playerEntity.hasComponent(TeamMember):
    result = gs.room.getTeam(gs.playerEntity[teamMember].team)

proc requestUnspec ( gs: PRoomGS; vehicle: string) =
  try:
    var(has, ent_id) = gs.room.requestUnspec(gs.player_id, vehicle)
    if has:
      gs.unspec(ent_id)
  except EInvalidKey:
    warn "Missing vehicle $#", vehicle
    discard

proc buildPlayerlist (gs: PRoomGS) =
  # team/player menu
  if not gs.playerListMenu.isNil:
    gs.gui.remove gs.playerListMenu
  
  let playerListMenu = newUL()
  
  block:
    var titleBar = newHL(padding = 4)
    titleBar.add textWidget("Playerlist", gs.guiFontSettings)
    titleBar.add(button("[-]", gs.guiFontSettings) do: 
      playerListMenu.sons[1].WidgetHideable.visible.toggle
    )
    playerListMenu.add titleBar
    
  block:
    let 
      playerList = hideable(newUL(), true)
      playerTeam = gs.playerTeam
    
    for team in gs.room.teamSys.teams:
      
      var fs = gs.playerDat.fontSettings
      if playerTeam and team.id == playerTeam.val.id:
        fs.color = green
      
      if team.members.len > 0:
        # has players
        var section = newUL()
        section.add(textWidget(team.name, fs))
        
        for ent_id in team.members:
          section.add(textWidget(gs.room.getEnt(ent_id).getName, fs))
        
        playerList.child.add section
    
    playerListMenu.add playerList

  
  
  playerListMenu.setPos point2d( 500,5 )
  let pos = point2d(g.window.getSize.x.float - playerListMenu.getBB.width - 4, 4)
  playerListMenu.setPos pos
  
  gs.playerListMenu = playerListMenu
  gs.gui.add gs.playerListMenu

proc reload (gs: PRoomGS) =
  gamedata = load_game_data(gamedata.dir)
  g.replace newRoomGS(gs.room.name)
 
proc initGui (gs: PRoomGS; r: PJsonNode) =

  let main_gui = newWidget()
  
  #skill menu
  var skm = hideable( newUL(), false )
  block:
    var hl = newHL(padding = 4)
    hl.add(textWidget("Choose Vehicle", gs.guiFontSettings))
    hl.add(button("[x]", gs.guiFontSettings) do: skm.visible = false)
    skm.child.add hl
  withKey(r, "playable", playable):
    for p in playable:
      let name = p.str
      let b = button(name, gs.guiFontSettings) do:
        gs.requestUnspec(name)
        skm.visible = false
      skm.child.add b
  skm.setPos point2d(100,100)
  
  #choose room menu
  let roomMenu = newUL()
  for name, data in gs.room.gamedata.rooms:
    let n = name
    let b = button(n, gs.guiFontSettings) do:
      echo "Switching to ", n
      g.replace(newRoomGS(n))
    roomMenu.add b
  
  #pause menu
  let pauseMenu = hideable(newUL(), false)
  pauseMenu.child.add(button("goto room", gs.guiFontSettings) do:
    main_gui.add roomMenu
    pauseMenu.visible = false
  )
  pauseMenu.child.add(button("reload", gs.guiFontSettings) do:
    gs.reload
  )
  pauseMenu.child.add(button("quit", gs.guiFontSettings) do:
    g.pop
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
  gs.updatePlayerRadar
  
  gs.radarTimer = newClock()


proc removeRCM (gs: PRoomGS) =
  if not gs.rcm.isNil:
    gs.gui.remove gs.rcm

proc makeRightClickMenu (gs: PRoomGS; ent_id: int) =
  let result = newUL()
  template hideRCM: stmt = 
    gs.removeRCM
  
  result.add onclick(textWidget(gs.room.getEnt(ent_id).getName, gs.guiFontSettings)) do:
    hideRCM
  result.add button("destroy",gs.guiFontSettings) do:
    gs.room.doom(ent_id) #destroyEnt(ent_id)
    hideRCM
  
  if gs.player.mode == Spectator:
    result.add button("spectate", gs.guiFontSettings) do:
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
  chkInput(fireEmitter1)

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

  if evt.kind == evtKeyPressed and evt.key.code == key_escape:
    gs.pause
    return

  if gs.player.isSpec:
    case evt.kind
    of evtKeyPressed:
      case evt.key.code
      
      of key_D:
        gs.debugDrawEnabled = not gs.debugDrawEnabled
        
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

        var ent = newEnt(gs.room, gs.room.gameData.randomFromGroup("asteroids"))
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
    
    const cameraSpeed = 16
    var offs: TVector2d
    if ic.turnRight:
      offs.x += cameraSpeed
    elif ic.turnLeft:
      offs.x -= cameraSpeed
    if ic.forward:
      offs.y -= cameraSpeed
    elif ic.backward:
      offs.y += cameraSpeed
    gs.playerEntity.setPos gs.playerEntity.getPos + offs

  else:
    if ic.spec:
      gs.spec

  gs.room.update dt
  let playerPos = gs.playerPos
  csfmlAudio.listenerSetPosition vec3f(playerpos.x, 0, playerpos.y)
  gs.camera.setCenter playerPos.vec2f

  if gs.radarTimer.getElapsedTime.asSeconds > 1.0: gs.updatePlayerRadar
  if not gs.player.isSpec:
    gs.vehicleGui.update

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

import browsers

type PLobbyState = ref object of PGameState
  gui: PWidget

proc lobbyState* : PGameState =
  let res = PLobbyState()
  res.gui = newWidget()
  
  var right_margin = 4.0
  var top_margin = 25.0
  
  # col 2
  let chooseZoneWidget: WidgetHideable = hideable(false)
  let loginForm: WidgetHideable = hideable(false)
  let helpMenu: WidgetHideable = hideable(false)
  
  template hide_all_right_cols: stmt =
    chooseZoneWidget.visible = false
    loginForm.visible = false
    helpMenu.visible = false
  
  block:
    let czm = newUL()
    czm.add textWidget("Choose zone.")
    for kind,dir in walkDir("data"):
      let D = dir.splitPath.tail
      czm.add(button(D) do:
        gameData = loadGameData(D)
        g.replace newRoomGS(gameData.firstRoom)
      )
    chooseZoneWidget.add czm
  block:
    let L = newUL()
    
    block:
      var un = newHL(padding=6)
      un.add textwidget("Username:")
      un.add textField("foo")
      L.add un
      
    block:
      var pw = newHL(padding=6)
      pw.add textWidget("Password:")
      pw.add textField("foo")
      L.add pw
    
    L.add(button("Login") do:
      let
        username = L.sons[0].sons[1].PTextfieldWidget.text
        passwd = L.sons[1].sons[1].PTextfieldWidget.text
      
      echo "Login $1 : $2".format(username,passwd)
    )
    loginForm.add L
  block:
    let H = newUL()
    H.add(button("Goto a website") do:
      openDefaultBrowser("http://github.com/fowlmouth/roids")
    )
    helpMenu.add H
  
  res.gui.add ChooseZoneWidget
  res.gui.add loginForm
  res.gui.add helpMenu
    
  # left column
  block:
    let opts_menu = newUL()
    opts_menu.add(button("Login") do:
      hide_all_right_cols
      loginForm.visible = true
    )
    opts_menu.add(button("Play offline") do:
      hide_all_right_cols
      chooseZoneWidget.visible = true
    )
    opts_menu.add(button("Help") do:
      hide_all_right_cols
      helpMenu.visible = true
    )
    opts_menu.setPos point2d(rightMargin,topMargin)
    res.gui.add opts_menu
    
    right_margin += opts_menu.getBB.width
  
  # col 2
  let pos = point2d(right_margin + 4, top_margin)
  chooseZoneWIdget.setPos pos
  loginForm.setPos pos
  helpMenu.setPos pos
  
  return res

method handleEvent* (GS:PLOBBYSTATE; EVT:VAR TEVENT) =
  if gs.gui.dispatch(evt): return

method draw * (W: PRenderWindow; gs: PLobbyState) =
  
  gs.gui.draw w


