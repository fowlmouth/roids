import strutils, json, basic2d, csfml, math
import chipmunk as cp except TBB
proc ff* (f: float; prec = 2): string = formatFloat(f, ffDecimal, prec)

# the penalty for having sfml vectors and chipmunk vectors
proc vector* [T: TNumber] (x, y: T): TVector = 
  result.x = x.cpfloat
  result.y = y.cpfloat
proc vector* (v: TVector2d): TVector =
  result.x = v.x
  result.y = v.y
proc vector* (v: TPoint2d): TVector = 
  result.x = v.x
  result.y = v.y
proc vec2f* (v: TVector): TVector2f = TVector2f(x: v.x, y: v.y)
proc vec2f* (v: TPoint2d): TVector2f = TVector2f(x: v.x, y: v.y)
proc vector2d* (v: TVector): TVector2d =
  result.x = v.x
  result.y = v.y

when not TVectorIsTVector2d:
  proc point2d* (v: TVector): TPoint2d =
    point2d(v.x, v.y)
proc point2d* (v: TVector2d): TPoint2d=
  point2d(v.x, v.y)
proc point2d* (p: TVector2i): TPoint2d = point2d(p.x.float, p.y.float)

proc distance*(a, b: TVector): float {.inline.} =
  return sqrt(pow(a.x - b.x, 2.0) + pow(a.y - b.y, 2.0))

proc `$`* (v: TVector2d): string =
  "($1,$2) $3".format(v.x.ff, v.y.ff, v.angle.radToDeg.ff) 

proc toggle* (switch: var bool){.inline.}=switch = not switch

proc toInt* (n: PJSonNode): int =
  case n.kind
  of jINT:
    result = n.num.int
  else:
    echo "this is not an int: ", n

proc toFloat* (n: PJsonNode): float =
  case n.kind
  of jInt:
    result = n.num.float
  of jFloat:
    result = n.fnum.float
  of jString:
    case n.str
    of "random":
      result = random(1.0)
    of "infinity":
      result = 1/0
  of jArray:
    case n[0].str
    of "random":
      # random(x) 
      result = random(n[1].toFloat)
    of "degrees":
      # degToRad(x)
      result = degToRad(n[1].toFloat)

  else:
    echo "Not a float value: ", n
proc getFloat* (result: var float; j: PJsonNode; key: string, default = 0.0) =
  if j.kind == JObject and j.hasKey(key):
    result = j[key].toFloat
  else:
    when defined(Debug):
      echo "Missing float key ",key
    result = default

proc vector2d* (n: PJSonNode): TVector2d =
  if n.kind == jString:
    case n.str
    of "random-direction":
      result = polarVector2d(deg360.random, 1.0)
    return
  
  assert n.kind == jArray
  if n[0].kind == jString:
    case n[0].str
    of "direction-degrees":
      result = polarVector2d(n[1].toFloat.degToRad, 1.0)
    
    of "v_*_f", "mul_f":
      result = n[1].vector2d * n[2].toFloat
    else:
      discard
    return
  
  result.x = n[0].toFloat
  result.y = n[1].toFloat
proc point2d* (n: PJsonNode): TPoint2d =
  assert n.len == 2
  result.x = n[0].toFloat
  result.y = n[1].toFLoat
  
proc getPoint* (result: var TPoint2d; j: PJsonNode; key: string; default = point2d(0,0)) =
  if j.kind == JObject and j.hasKey(key):
    result = point2d(j[key])
  else:
    result = default

proc getInt* (result:var int; j:PJsonNode; key:string; default = 0) =
  if j.kind == JObject and j.hasKey(key):
    case j[key].kind
    of jInt:
      result = j[key].num.int
    of jFloat:
      result = j[key].fnum.int
    else:
      echo "Not an int value: ", j[key]
      result = default
  else:
    when defined(Debug):
      echo "Missing int key ", key
    result = default


template withKey* (J: PJsonNode; key: string; varname: expr; body:stmt): stmt {.immediate.}=
  if j.hasKey(key):
    let varname{.inject.}= j[key]
    block:
      body

