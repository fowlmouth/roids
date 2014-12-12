import 
  basic2d,os,strutils,math,
  csfml,csfml_colors,
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
    callbacks*: TCallbackSet
    sons*: seq[PWidget]
    hasFocus: TMaybe[PWidget]
    master: PWidget
    
  TCallbackSet* = object
    update*: proc(G:PWidget)
    
  TWidgetVT* = object
    draw*: proc(G: PWidget; W: PRenderWindow)
    setPos*: proc(G: PWidget; P: TPoint2d)
    getBB*: proc(G: PWidget): TFloatRect
    onClick*: proc (g: PWidget; btn: TMouseButton; x, y: int): bool
    onFocus*: proc(G:PWidget; GAINED:bool)
    onTextEntered*: proc(G:PWidget; unicode:cint): bool

proc `$` (r: TFloatRect): string = 
  "($1,$2,$3,$4)".format(
    ff(r.left,1), ff(r.top,1), ff(r.width,1), ff(r.height,1))

proc draw* (g: PWidget; w: PRenderWindow){.inline.}=
  g.vtable.draw(g, w)
proc setPos* (g: PWidget; p: TPoint2d) {.inline.}=
  g.vtable.setPos(g,p)
proc getBB*(g: PWidget): TFloatRect {.inline.}=
  result = g.vtable.getBB(g)
proc onClick (g: PWidget; btn: TMouseButton; x, y: int): bool {.inline.}=
  result = g.vtable.onClick(g, btn, x,y)
proc onTextEntered (G:PWIDGET; UNICODE:cint): bool {.inline.} = 
  result = G.vtable.onTextEntered(G, Unicode)
proc onFocus (G:PWIDGET; GAINED:bool) {.inline.}=
  G.vtable.onFocus(G,Gained)

proc `update_f=`* (g:PWidget; f:proc(g:PWidget)) {.inline.} =
  g.callbacks.update = f 
proc update* (g: PWidget) {.inline.}=
  g.callbacks.update(g)


proc child*(g: PWidget): PWidget = g.sons[0]



proc dispatch* (g: PWidget; evt: var TEvent): bool =
  case evt.kind
  of EvtMouseButtonPressed:
    #
    result = g.onClick( evt.mouseButton.button, evt.mouseButton.x, evt.mouseButton.y )
    
  of EvtTextEntered:
    if g.hasFocus.has:
      result = g.hasFocus.val.onTextEntered(evt.text.unicode)
    else:
      result = g.onTextEntered(evt.text.unicode)
  else:
    discard


var
  defaultVT * = TWidgetVT()

defaultVT.draw = proc(g: PWidget; w: PRenderWindow) =
  if not(g.sons.isNil):
    for s in g.sons: draw(s, w)
defaultVT.setPos = proc(G: PWidget; P: TPoint2d) =
  discard
defaultVT.getBB = proc(g: PWidget):TFloatRect = 
  if not(g.sons.isNil) and g.sons.len > 0:
    result = g.sons[0].getBB
    for i in 1 .. g.sons.len - 1:
      result.expandToInclude g.sons[i].getBB

defaultVT.onClick = proc (g: PWidget; btn: TMouseButton; x, y: int): bool =
  if not g.sons.isNil:
    for id in countdown(high(g.sons), 0):
      if g.sons[id].onClick(btn,x,y):
        return true
defaultVT.onTextEntered = proc(g:PWIDGET; uNICODE:cint):bool =
  if not g.sons.isNil:
    for id in countdown(high(g.sons), 0):
      if g.sons[id].onTextEntered(unicode):
        return true
defaultVT.onFocus = proc(G:PWIDGET;GAINED:bool) =
  discard

proc default_update (g:PWidget) =
  if not g.sons.isNil:
    for widget in g.sons:
      update(widget)

proc `||=` [T:ref|ptr|proc] (L: var T; R: T) =
  if L.isNil: L = R

proc init* (g: PWidget; sons = 0) =
  g.callbacks.update ||= default_update
  if g.vtable.isNil: g.vtable = defaultVT.addr
  if g.sons.isNil: g.sons.newSeq sons


proc takeFocus* (w:PWIDGET) =
  if w.master.isNil:
    return
  if w.master.hasFocus.has: w.master.hasFocus.val.onFocus(false)
  w.master.hasFocus = Just(w)
  w.onFocus true

proc newWidget*: PWidget =
  result = PWidget(vtable: defaultVT.addr)
  result.init
  result.master = result


proc add* (g: PWidget; w: PWidget)=
  g.sons.add(w)
  w.master = g.master
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
defaultFontSettings.color = White
proc newText* (settings: TFontSettings; str = ""): PText = 
  result = newText(str, settings.font, settings.characterSize.cint)
  result.setColor settings.color


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
  result.text = font.newText(str)
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
hlVT.setPos = proc(g:PWidget; p:TPoint2d)=
  var pos = p
  for c in g.sons:
    c.setPos pos
    pos.x += c.getBB.width + g.WidgetHL.padding

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
  g.child.getBB
hideableVT.onClick = proc(g:PWidget; btn:TMouseButton;x,y:int): bool =
  if g.WidgetHideable.visible:
    result = defaultVT.onClick(g, btn,x,y)
hideableVT.onTextEntered = proc(g:PWIDGET; unicode:cint):bool =
  if g.WidgetHideable.visible:
    result = defaultVT.onTextEntered(g,unicode)

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
clckVT.draw = proc(g: PWidget; w: PRenderWindow) =
  g.sons[0].draw w
clckVT.getBB = proc(g: PWidget):TFloatRect=
  g.sons[0].getBB
clckVT.onClick = proc(g:PWidget; btn:TMouseButton;x,y:int):bool=
  if (x,y) in g.getBB:
    g.WidgetClickable.cb()
    result = true
clckVT.setPos = proc(g:PWidget; p:TPoint2d)=
  g.sons[0].setPos p

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
  originalText*: string
  cursor*: int
  clearOnClick: TMaybe[bool] # the inner val is whether it has been cleared
  chars: set[char]


proc updateSFtext (G:PTextfieldWidget) =
  G.child.WidgetText.text.setString G.text
proc setText* (G:PTextfieldWidget; text:string) =
  G.text = text
  G.updateSfText()

var tfWidget = defaultVT
tfWidget.draw = proc(g:PWIDGET; w:PRenderWindow)=
  g.child.draw w
tfWidget.setPos = proc(g:PWIDGET; pos:TPOINT2D) = 
  g.child.setPos pos
  
tfWidget.onTextEntered = proc(g: PWidget; unicode: cint): bool =
  let g = g.Ptextfieldwidget
  if unicode == '\b'.ord:
    if g.cursor > 0:
      # delet
      if g.cursor > g.text.len: g.cursor = g.text.len
      let rem = g.text[g.cursor .. -1]
      g.text.setLen g.cursor-1
      g.text.add rem
      g.updateSFtext
      g.cursor = max(0, g.cursor-1)
      result = true
  elif unicode < 256 and unicode.char in g.chars:
    let c = unicode.char
    g.text.add c
    g.updatesftext
    inc g.cursor
    result = true

tfWidget.onFocus = proc(g:PWIDGET; gained:bool) =
  let g = g.PTEXTFIELDWIDGET
  if not gained and g.text == "":
    g.setText g.originalText
  elif gained and g.clearOnClick.has and g.text == g.originalText:
    g.setText ""


tfWidget.getBB = proc(g:PWidget):TFloatRect =
  result = g.child.getBB
tfWidget.onClick = proc(g:PWIDGET; BTN:TMOUSEBUTTON; x,y:int): bool =
  if (x,y) in g.getBB:
    # take focus
    g.takeFocus
    result = true


proc textfield*(defaultText: string; 
        fontSettings = defaultFontSettings;
        allowedCharacters = {'\x20' .. '\x7E'}; 
        clearOnClick = true): PTextfieldWidget =
  new(result) do (X:PTextfieldWidget):
    #destroy x.sfText
    discard
  #result.sfText = fontSettings.newText
  result.vtable = tfWidget.addr
  result.sons = @[ textWidget(defaultText, fontSettings).PWidget ]
  result.init
  result.clearOnClick.has = clearOnClick
  result.text = defaultText
  result.originalText = defaultText
  result.chars = allowedCharacters
  

