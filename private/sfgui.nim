
import csfml, basic2d,os

proc right* (bb: TFloatRect): cfloat = bb.left + bb.width
proc bottom*(bb: TFloatRect): cfloat = bb.top + bb.height

proc contains* (bb: TFloatRect; point: tuple[x,y: int]): bool =
  point.x.cfloat >= bb.left and point.x.cfloat <= bb.right and
    point.y.cfloat >= bb.top and point.y.cfloat <= bb.bottom

proc findFile (f: string; dirs: seq[string]): string =
  let oldD = getCurrentDir()
  block foo:
    for d in dirs:
      setCurrentDir d
      for file in walkFiles(f):
        result = d / file
        break foo
  setCurrentDir oldD

proc systemFont* (f: string): PFont =
  var searchDirs: seq[string] = @[]
  when defined(linux):  
    searchDirs.add  "/usr/share/fonts/TTF"
  
  let f = find_file(f, searchDirs)
  if not f.isNil:
    result = newFont(f)

type
  PWidget* = ref object of TObject
#    draw*: proc(w: PRenderWindow; g: PWidget)

var
  defaultFont* = systemFont("LiberationSans-Regular.ttf")

type EGUI* = object of EBase
template unkMethod (m): stmt = 
  raise newException(EGUI, "Please implement "& m &" method.")

method draw* (w: PRenderWindow; g: PWidget) =
  unkMethod "draw"
method setPos* (g: PWidget; x, y: float) =
  unkMethod "setPos"
method handleClick* (g: PWidget; x, y: int):bool =
  unkMethod "handleClick"
method getLocalBB* (g: PWidget): TFloatRect =
  unkMethod "getLocalBB"
method update* (g: PWidget; dt: float) = 
  unkMethod "update"

proc dispatch* (w: PWidget; evt: var TEvent): bool = 
  if evt.kind == evtMouseButtonPressed:
    if evt.mouseButton.button == mouseLeft:
      return w.handleClick(evt.mouseButton.x, evt.mouseButton.y)

type
  PTextWidget* = ref object of PWidget
    text: PText

proc setText* (w: PTextWidget; s: string) =
  w.text.setString s
proc initText (p: PTextWidget; s: string) =
  let t = newText()
  t.setFont defaultFont
  t.setCharacterSize 14
  p.text = t

proc newTextWidget* (s: string): PTextWidget =
  result = PTextWidget()
  initText result, s
    
method draw* (W: PRenderWindow; g: PTextWidget) =
  w.draw g.text

method getLocalBB* (g: PTextWidget): TFloatRect =
  g.text.getLocalBounds

method setPos* (g: PTextWidget; x, y: float) =
  g.text.setPosition(vec2f(x, y))
method update* (g: PTextWidget; dt:float) = 
  nil
method handleClick*(g: PTextWidget; x,y: int):bool=
  echo "Ignored handleClick on ptextwidget ", g.text.getString

type
  PButton* = ref object of PTextWidget
    onClick*: proc()


method handleClick* (g: PButton; x, y: int) : bool =
  if (x, y) in g.text.getGlobalBounds:
    g.onClick()
    result = true

proc newButton* (text: string; onClick: proc()): PButton =
  result = PButton(onClick: onCLick)
  result.initText text


type
  PCollection* = ref object of PWidget
    ws: seq[PWidget]

proc initCollection (w: PCollection) =
  w.ws = @[]
proc newCollection* : PCollection =
  new result
  result.initCollection

proc add* (w: PCollection; w2: PWidget) {.inline.}=
  w.ws.add w2
proc remove* (w: PCollection; w2: PWidget) {.inline.} =
  let id = w.ws.find(w2)
  if id != -1: w.ws.delete(id)

method draw* (w: PRenderWindow; col: PCollection) =
  for widget in col.ws:
    w.draw widget

method handleClick* (w: PCollection; x,y: int): bool = 
  for widget in w.ws:
    result = widget.handleClick(x,y)
    if result: return
method update* (w: PCollection; dt: float) =
  for wid in w.ws: wid.update(dt)



type
  PW_UL* = ref object of PCollection
    pos: TPoint2d

proc realign* (w: PW_UL) =
  var p = w.pos
  for widget in w.ws:
    widget.setPos p.x, p.y
    p.y += widget.getLocalBB.height

proc newUL* (): PW_UL =
  result = PW_UL()
  result.initCollection

method setPos* (w: PW_UL; x, y: float) =
  w.pos.x = x
  w.pos.y = y
  w.realign
  echo w.ws.len

method getLocalBB* (g: PWUL): tFLoatRect =
  for w in g.ws:
    let bb = w.getLocalBB
    result.height += bb.height
    result.width = max(result.width, bb.width)

type
  PHideable* = ref object of PWidget
    visible*: bool
    w*: PWidget

proc newHideable* (w: PWidget, visible = true) : PHideable =
  result = PHideable (w: w, visible: visible)

method draw* (w: PRenderWindow; g: PHideable) =
  if g.visible:
    w.draw g.w
method setPos* (w: PHideable; x,y: float) =
  w.w.setPos x,y
method handleClick* (w: PHideable; x,y: int): bool = 
  if w.visible:
    result = w.w.handleClick(x,y)
method update* (g: PHideable; dt: float) =
  if g.visible: g.w.update dt
method getLocalBB* (g: PHideable): TFloatRect=
  g.w.getLocalBB

type
  PUpdateable* = ref object of PWidget
    w*: PWidget
    f: proc() {.closure.}

method draw* (w: PRenderWindow; g: PUpdateable) =
  w.draw g.w
method setPos* (g: PUpdateable; x,y: float) =
  g.w.setPos x,y
method update* (g: PUpdateable; dt: float) =
  g.f()
method getLocalBB* (g: PUpdateable): TFloatRect =
  g.w.getLocalBB
method handleClick*(g: PUpdateable;x,y: int): bool=
  result = g.w.handleClick(x,y)

proc newUpdateable* (w: PWidget; f: proc()): PUpdateable =
  result = PUpdateable(
    w: w,
    f: f
  )


