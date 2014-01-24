import chipmunk as cp
import csfml,csfml_colors, private/components

proc debugDrawShape (shape: cp.PShape; w: PRenderWindow){.cdecl.}=
  case shape.klass.kind
  of cp_circle_shape:
    var c {.global.} = newCircleShape(1.0, 30)
    c.setPosition shape.getBody.p.vec2f
    let r = shape.getCircleRadius
    c.setRadius r
    c.setOrigin vec2f(r,r)
    var color = white
    if shape.getSensor:
      color.a = 30
      c.setOutlineThickness 1.0
    else:
      color.a = 70
      c.setOutlineThickness 0.0
    c.setFillColor(color)
    w.draw c
  of cp_segment_shape:
    var s {.global.} = newVertexArray(csfml.Lines, 2)
    s[0].position = shape.getSegmentA.vec2f
    s[1].position = shape.getSegmentB.vec2f
    w.draw s
  else:
    discard

proc debugDraw* (w: PRenderWindow; space: PSpace) =
  space.eachShape(cast[TSpaceShapeIteratorFunc](debugDrawShape), cast[pointer](w))
