import 
  private/gsm, private/sfgui2, private/gamestates,
  basic2d,
  csfml

type
  PPauseGS* = ref object of PGameState
    gui: sfgui2.PWidget

proc newPauseGS* : PGameState =
  let res = PPauseGS()
  res.gui = sfgui2.newWidget()
  
  let ul = sfgui2.newUL()
  let btn = button("[escape to unpause]") do:
    g.pop
  ul.add btn

  let quitbtn = button("quit") do:
    g.window.close
  ul.add quitbtn
  ul.setPos point2d(100,100)
  
  res.gui.add ul
  
  return res
method handleEvent* (gs: PPauseGS; evt: var TEvent) =
  if gs.gui.dispatch(evt): return
  
  if evt.kind == evtKeyPressed and evt.key.code == keyEscape:
    g.pop
    
method draw* (w: PRenderWindow; gs: PPauseGS) =
  # draw the last gamestate
  w.draw g.past
  
  gs.gui.draw w
