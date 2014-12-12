import csfml, csfml_colors, private/sfgui2
export csfml
type
  PGameState* = ref object of TObject

method draw* (w: PRenderWindow; gs: PGameState) = 
  nil

method handleEvent* (gs: PGameState; evt: var TEvent) =
  nil

method update* (gs: PGamestate; dt: float) =
  nil

type
  PGod* = ref object
    w: PRenderWindow
    clock: PClock
    state: seq[PGameState]
    sp: int

type
  PWIYG = ref object of PGameState
    text:PText

method draw* (w: PRenderWindow; gs: PWIYG) = 
  w.draw gs.text
proc whoIsYourGod : PGameState =
  let res = PWIYG()
  res.text = newText("Who is your god?", sfgui2.defaultFont, 14)
  res.text.setColor Green
  res.text.setPosition vec2f(10,10)
  return res

proc newGod* (vm: TVideoMode; caption = "foo", style = sfDefaultStyle; firstState = whoIsYourGod()): PGod =
  result = PGod(w: newRenderWindow(vm, caption, style.int32))
  result.clock = newClock()
  result.state = @[ firstState ]
  result.sp = 0

proc window*(g: PGod):PRenderWindow=g.w
proc topGS* (g: PGod): PGameState = g.state[g.sp]
proc past*  (g: PGod): PGameState = g.state[< g.sp]
proc pop* (g: PGod) =
  dec g.sp
  g.state.setLen g.sp+1

proc push* (g: PGod; gs: PGameState) = 
  g.state.add gs
  g.sp.inc
proc replace* (g: PGod; gs: PGameState) =
  if g.state.len > g.sp+1:
    g.state.setLen g.sp+1
  g.state[g.sp] = gs

proc run* (g: PGod) =
  var evt: TEvent
  while g.w.isOpen:
    while g.w.pollEvent(evt):
      if evt.kind == EvtClosed: 
        g.w.close
        break
      g.topGS.handleEvent evt
    
    
    g.topGS.update g.clock.restart.asMilliseconds/1000
    
    g.w.clear Black
    g.w.draw g.topGS
    g.w.display


when isMainModule:
  var g = newGod(videoMode(800,600,32),"Hello")
  g.run


