import csfml,basic2d,os


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

var
  defaultFont* = systemFont("LiberationSans-Regular.ttf")

type
  PWidget* = ref object{.inheritable.}
    vtable*: ptr TWidgetVT
    sons*: seq[PWidget]
  
  TWidgetVT* = object
    draw*: proc(G: PWidget; W: PRenderWindow)
    setPos*: proc(G: PWidget; P: TPoint2d)
    getBB*: proc(G: PWidget): TFloatRect
    onClick*: proc (g: PWidget; btn: TMouseButton; x, y: int): bool 


proc draw* (g: PWidget; w: PRenderWindow){.inline.}=
  g.vtable.draw(g, w)
proc setPos* (g: PWidget; p: TPoint2d) {.inline.}=
  g.vtable.setPos(g,p)
proc getBB*(g: PWidget): TFloatRect {.inline.}=
  g.vtable.getBB(g)
proc onClick (g: PWidget; btn: TMouseButton; x, y: int): bool {.inline.}=
  result = g.vtable.onClick(g, btn, x,y)

proc child*(g: PWidget): PWidget = g.sons[0]

var
  defaultVT = TWidgetVT()

defaultVT.draw = proc(G: PWidget; W: PRenderWindow) =
  for s in g.sons: draw(s, w)
defaultVT.setPos = proc(G: PWidget; P: TPoint2d) =
  discard
defaultVT.getBB = proc(G: PWidget):TFloatRect = 
  discard
defaultVT.onClick = proc (g: PWidget; btn: TMouseButton; x, y: int): bool =
  if not g.sons.isNil:
    for s in g.sons:
      if s.onClick(btn,x,y):
        return true

proc init* (g: PWidget; sons = 0) =
  g.sons.newSeq sons

proc newWidget*: PWidget =
  result = PWidget(vtable: defaultVT.addr)
  result.init


proc dispatch* (g: PWidget; evt: var TEvent): bool =
  case evt.kind
  of EvtMouseButtonPressed:
    #
    result = g.onClick( evt.mouseButton.button, evt.mouseButton.x, evt.mouseButton.y )
  else:
    #

proc add* (g: PWidget; w: PWidget)=
  g.sons.add(w)
proc remove*(g: PWidget; w: PWidget)=
  let id = g.sons.find(w)
  if id != -1: g.sons.delete id

discard """ type
  WidgetCollection* = ref object of PWidget
method draw*(g: WidgetCollection;w:PRenderWindow) =
  for ww in g.sons: ww.draw(w)
method onClick*(g: WidgetCollection;btn:TMouseButton;x,y:int):bool=
  for ww in g.sons:
    if ww.onClick(btn,x,y):
      return true
proc newCollection* : PWidget =
  result = WidgetCollection()
  result.init
 """
type
  WidgetText* = ref object of PWidget
    text: PText

var textWidgetVT = defaultVT
textWidgetVT.getBB = proc(t: PWidget): TFloatRect =
  t.WidgetText.text.getGlobalBounds
textWidgetVT.setPos = proc(t: PWidget; p: TPoint2d)=
  t.WidgetText.text.setPosition vec2f(p.x,p.y)
textWidgetVT.draw = proc(t: PWidget; w: PRenderWindow)=
  w.draw t.WidgetText.text
textWidgetVT.onCLick = proc(t: PWidget;btn:TMouseButton; x,y: int): bool =
  false


proc textWidget* (str: string; font = defaultFont): WidgetText =
  new(result) do (obj: WidgetText):
    destroy obj.text
  result.text = newText(str,font,18)
  result.vtable=textWidgetVT.addr

type
  Widget_UL* = ref object of PWidget
    pos*: TPoint2d

var ulVT = defaultVT
ulVT.setPos = proc(g: PWidget; p: Tpoint2d)=
  g.WidgetUL.pos = p
  var pos = p
  for c in g.sons:
    c.setPos pos
    pos.y += c.getBB.height

proc newUL* : PWidget =
  result = WidgetUL(vtable: ulVT.addr)
  result.init

discard """ method setPos* (g: WidgetUL; p: TPoint2d) =

method draw* (g: WidgetUL; w: PRenderWindow) =
  for c in g: c.draw(w)

method onClick* (g: WidgetUL; btn: TMouseButton; x,y: int): bool =
  for w in g.sons:
    if w.onClick(btn,x,y):
      return true
 """
type
  WidgetHideable* = ref object of PWidget
    visible*: bool

var hideableVT = defaultVT
hideableVT.draw = proc(g: PWidget; w: PRenderWindow)=
  if g.WidgetHideable.visible:
    g.sons[0].draw w
hideableVT.setPos = proc(g: PWidget; p: TPoint2d)=
  g.sons[0].setPos p
hideableVT.getBB = proc (g: PWidget): TFloatRect=
  result = g.sons[0].getBB
hideableVT.onClick = proc(g:PWidget; btn:TMouseButton;x,y:int): bool =
  if g.WidgetHideable.visible: result = g.sons[0].onClick(btn,x,y)


proc hideable*(w: PWidget; visible = true): WidgetHideable =
  result = WidgetHideable(visible:visible, sons: @[w], vtable: hideableVT.addr)


type
  WidgetClickable* = ref object of PWidget
    cb*: proc()

var clckVT = defaultVT
clckVT.draw = proc(G: PWidget; w: PRenderWindow) =
  g.sons[0].draw w
clckVT.getBB = proc(G: PWidget):TFloatRect=
  g.sons[0].getBB
clckVT.onClick = proc(G:PWidget; btn:TMouseButton;x,y:int):bool=
  if (x,y) in g.getBB:
    g.WidgetClickable.cb()
    result = true
clckVT.setPos = proc(G:PWidget; p:TPoint2d)=
  G.sons[0].setPos p

proc onClick*(w: PWidget; f: proc()): WidgetClickable=
  WidgetClickable(
    cb: f,
    sons: @[w],
    vtable: clckVT.addr
  )
proc button*(str:string; f:proc()): WidgetClickable =
  result = onClick(textWidget(str), f)

discard """ method draw* (g: WidgetCLickable; w: PRenderWindow)=
  g.sons[0].draw w
method getBB* (g: WidgetClickable): TFloatRect=
  result = g.sons[0].getBB
method onClick* (g: WidgetClickable; btn:TMouseButton;x,y:int):bool =
method setPos* (g: WidgetClickable; p: TPoint2d)=
  g.sons[0].setPos p
 """