import csfml,basic2d,os,strutils,math,csfml_colors,
  fowltek/maybe_t
proc ff (f:float;prec=2):string = formatFloat(f,ffDecimal,prec)


proc right* (bb: TFloatRect): cfloat = bb.left + bb.width
proc bottom*(bb: TFloatRect): cfloat = bb.top + bb.height

proc contains* (bb: TFloatRect; point: tuple[x,y: int]): bool =
  point.x.cfloat >= bb.left and point.x.cfloat <= bb.right and
    point.y.cfloat >= bb.top and point.y.cfloat <= bb.bottom
proc expandToInclude* (bb: var TFloatRect; bb2: TFloatRect) =
  bb.left = bb.left.min(bb2.left)
  bb.top = bb.top.min(bb2.top)
  bb.width = bb.right.max(bb2.right) - bb.left
  bb.height = bb.bottom.max(bb2.bottom) - bb.top

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
    update_f*: proc(G: PWidget)
  
  TWidgetVT* = object
    draw*: proc(G: PWidget; W: PRenderWindow)
    setPos*: proc(G: PWidget; P: TPoint2d)
    getBB*: proc(G: PWidget): TFloatRect
    onClick*: proc (g: PWidget; btn: TMouseButton; x, y: int): bool
    onTextEntered*: proc(G:PWidget; unicode:cint): bool

proc `$` (r: TFloatRect): string = 
  "($1,$2,$3,$4)".format(
    ff(r.left,1), ff(r.right,1), ff(r.width,1), ff(r.height,1))

proc draw* (g: PWidget; w: PRenderWindow){.inline.}=
  g.vtable.draw(g, w)
proc setPos* (g: PWidget; p: TPoint2d) {.inline.}=
  g.vtable.setPos(g,p)
proc getBB*(g: PWidget): TFloatRect {.inline.}=
  result = g.vtable.getBB(g)
proc onClick (g: PWidget; btn: TMouseButton; x, y: int): bool {.inline.}=
  result = g.vtable.onClick(g, btn, x,y)
proc onTextEntered (G:PWIDGET; UNICODE:CINT): BOOL {.inline.} = 
  result = g.vtable.onTextEntered(g, unicode)
proc update* (g: PWidget) {.inline.}=
  g.update_f(g)

proc child*(g: PWidget): PWidget = g.sons[0]



proc dispatch* (g: PWidget; evt: var TEvent): bool =
  case evt.kind
  of EvtMouseButtonPressed:
    #
    result = g.onClick( evt.mouseButton.button, evt.mouseButton.x, evt.mouseButton.y )
  of EvtTextEntered:
    result = g.onTextEntered(evt.text.unicode)
  else:
    #


var
  defaultVT * = TWidgetVT()

defaultVT.draw = proc(G: PWidget; W: PRenderWindow) =
  if not(g.sons.isNil):
    for s in g.sons: draw(s, w)
defaultVT.setPos = proc(G: PWidget; P: TPoint2d) =
  discard
defaultVT.getBB = proc(G: PWidget):TFloatRect = 
  if not(g.sons.isNil) and g.sons.len > 0:
    result = g.sons[0].getBB
    for i in 1 .. g.sons.len - 1:
      result.expandToInclude g.sons[i].getBB

defaultVT.onClick = proc (g: PWidget; btn: TMouseButton; x, y: int): bool =
  if not g.sons.isNil:
    for id in countdown(high(g.sons), 0):
      if g.sons[id].onClick(btn,x,y):
        return true
defaultVT.onTextEntered = proc(G:PWIDGET; UNICODE:CINT):BOOL =
  if not g.sons.isNil:
    for id in countdown(high(g.sons), 0):
      if g.sons[id].onTextEntered(unicode):
        return true

proc default_update (G:PWidget) =
  if not g.sons.isNil:
    for widget in g.sons:
      update(widget)

proc init* (g: PWidget; sons = 0) =
  if g.update_f.isNil: g.update_f = default_update
  if g.vtable.isNil: g.vtable = defaultVT.addr
  if g.sons.isNil: g.sons.newSeq sons

proc newWidget*: PWidget =
  result = PWidget(vtable: defaultVT.addr)
  result.init


proc add* (g: PWidget; w: PWidget)=
  g.sons.add(w)
proc remove*(g: PWidget; w: PWidget)=
  let id = g.sons.find(w)
  if id != -1: g.sons.delete id

type
  TFontSettings* = tuple
    font: PFont
    characterSize: int
    color: TColor
var defaultFontSettings*: TFontSettings
defaultFontSettings.font = defaultFont
defaultFontSettings.characterSize = 18
defaultFontSettings.color = white

type
  WidgetText* = ref object of PWidget
    text*: PText

var textWidgetVT = defaultVT
textWidgetVT.getBB = proc(t: PWidget): TFloatRect =
  t.WidgetText.text.getGlobalBounds
textWidgetVT.setPos = proc(t: PWidget; p: TPoint2d)=
  t.WidgetText.text.setPosition vec2f(p.x,p.y)
textWidgetVT.draw = proc(t: PWidget; w: PRenderWindow)=
  w.draw t.WidgetText.text
textWidgetVT.onCLick = proc(t: PWidget;btn:TMouseButton; x,y: int): bool =
  false


proc textWidget* (str: string; font = defaultFontSettings): WidgetText =
  new(result) do (obj: WidgetText):
    destroy obj.text
  result.init
  result.text = newText(str, font.font, font.characterSize.cint)
  result.vtable=textWidgetVT.addr

type
  Widget_UL* = ref object of PWidget
    padding*: float
#    pos*: TPoint2d

var ulVT = defaultVT
ulVT.setPos = proc(g: PWidget; p: Tpoint2d)=
  var pos = p
  for c in g.sons:
    c.setPos pos
    pos.y += c.getBB.height + g.WidgetUL.padding

proc newUL* (padding = 2.0) : PWidget =
  result = WidgetUL(padding: padding, vtable: ulVT.addr)
  result.init

type WidgetHL* = ref object of PWidget
  padding*: float
var hlVT = defaultVT
hlVT.setPos = proc(G:PWidget; P:TPoint2d)=
  var pos = p
  for c in g.sons:
    c.setPos pos
    pos.x += c.getBB.width + g.widgetHL.padding

proc newHL* (padding = 2.0) : PWidget =
  result = WidgetHL(padding: padding, vtable: hlVT.addr)
  result.init

type
  WidgetHideable* = ref object of PWidget
    visible*: bool

var hideableVT = defaultVT
hideableVT.draw = proc(g: PWidget; w: PRenderWindow)=
  if g.WidgetHideable.visible:
    defaultVT.draw(g, w)
hideableVT.setPos = proc(g: PWidget; p: TPoint2d)=
  g.child.setPos p
hideableVT.getBB = proc (g: PWidget): TFloatRect=
  G.child.getBB
hideableVT.onClick = proc(g:PWidget; btn:TMouseButton;x,y:int): bool =
  if g.WidgetHideable.visible:
    result = defaultVT.onClick(g, btn,x,y)


proc hideable*(w: PWidget; visible = true): WidgetHideable =
  result = WidgetHideable(visible:visible, sons: @[w], vtable: hideableVT.addr)
  result.init
proc hideable*(visible = true): WidgetHideable =
  result = WidgetHideable(visible: visible, vtable: hideableVT.addr)
  result.init

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
  result = WidgetClickable(
    cb: f,
    sons: @[w],
    vtable: clckVT.addr
  )
  result.init
proc button*(str:string; f:proc()): WidgetClickable =
  result = onClick(textWidget(str, defaultFontSettings), f)
proc button*(str:string; fontSettings: TFontSettings; f:proc()): WidgetClickable =
  result = onClick(textWidget(str, fontSettings), f)


type PTextfieldWidget* = ref object of PWidget
  text*: string
  cursor*: int
  clearOnClick: TMaybe[bool] # the inner val is whether it has been cleared


proc updateSFtext (G:PTextfieldWidget) =
  G.child.widgetText.text.setString G.Text
proc setText* (G:PTextfieldWidget; text:string) =
  G.text = text
  G.updateSfText()

var tfWidget = defaultVT
tfWidget.draw = proc(G:PWIDGET; W:PRenderWindow)=
  g.child.draw w
tfWidget.setPos = proc(G:PWIDGET; POS:TPOINT2D) = 
  G.child.setPos pos
  
tfWidget.onTextEntered = proc(G: PWidget; unicode: cint): bool =
  if unicode.char == '\b' and G.PTextfieldWidget.cursor > 0:
    # delet
  else:
    let c = unicode.char
    let g = g.ptextfieldwidget
    g.text.add c
    g.updatesftext
    echo "Captured text: ", c, " (", c.ord,")"
    result = true

tfWidget.getBB = proc(G:PWidget):TFloatRect =
  result = g.child.getBB
tfWidget.onClick = proc(G:PWIDGET; BTN:TMOUSEBUTTON;X,Y:INT): BOOL =
  if btn != mouseLeft: return
  
  let g = g.PTextfieldWidget
  if (x,y) in g.getBB: 
    if g.clearOnClick and not g.clearOnClick.val:
      g.setText ""
      g.clearOnClick.val = true

proc newText* (settings: TFontSettings): PText = 
  result = newText("", settings.font, settings.characterSize.cint)
  result.setColor settings.color

proc textfield*(defaultText: string; fontSettings = defaultFontSettings; clearOnClick = true): PTextfieldWidget =
  new(result) do (X:PTextfieldWidget):
    #destroy x.sfText
  #result.sfText = fontSettings.newText
  result.vtable = tfWidget.addr
  result.sons = @[ textWidget(defaultText, fontSettings).PWidget ]
  result.init
  result.clearOnClick.has = clearOnClick
  result.setText defaultText

