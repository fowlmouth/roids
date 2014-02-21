# I stole this with love from the SFML wiki
# https://github.com/LaurentGomila/SFML/wiki/Source%3A-Color-Gradient
# original author: some chap named mooglwy

import csfml, csfml_colors, tables, math, algorithm

type TColorPos = tuple[pos:float, color: TColor]
type TColorScale* = object
  colors: seq[TColorPos]

proc initColorScale* : TColorScale =
  result.colors.newSeq 0

type TInterpolationFunc* = proc(a, b: float; mu: float)
proc linearInterp* (v1, v2: float; mu: float): float {.procvar.} =
  v1 * (1 - mu) + v2 * mu
proc cosinusInterp*(y1, y2: float; mu: float): float {.procvar.} =
  let mu2 = (1 - cos(mu * PI)) / 2
  y1 * (1 - mu2) + y2 * mu2

proc fill* (T: var TColorScale; result: var seq[TColor]; func = linearInterp) =
  T.colors.sort do (a,b: TColorPos)->int: cmp(a.pos, b.pos)
  
  let 
    lastColorIDX = T.colors.len - 1
    distance = T.colors[lastColorIDX].pos - T.colors[0].pos
    len = result.len
  var
    i = 0
    pos = 0.0
  
  while i != lastColorIDX:
    var 
      startColor = T.colors[i].color
      startPos   = T.colors[i].pos
    inc i
    var
      endColor = T.colors[i].color
      endPos   = T.colors[i].pos
    let
      nb_color = (endPos - startPos) * len.float / distance
    
    for i in pos.int .. (pos + nb_color).int - 1:
      template min0 (num): expr = max(0.0, num)
      template f (field): expr = uint8( func(startColor.field.float, endColor.field.float, min0(i.float - pos) / (nb_color - 1.0)) )
      result[i].r = f(r)
      result[i].g = f(g)
      result[i].b = f(b)
      result[i].a = f(a)
    pos += nb_color  

proc toSeq* (T: var TColorScale; len: int; func = linearInterp): seq[TColor] =
  newSeq result, len
  T.fill result, func


proc insert* (T:var TColorScale; key:float; color:TColor) {.inline.} =
  T.colors.add((key, color))

when isMainModule:
  var gradient = initColorScale()
  gradient.insert 0.0, red
  gradient.insert 0.5, yellow
  gradient.insert 1.0, green

  var colors = gradient.toSeq(11)

  echo repr(colors)


