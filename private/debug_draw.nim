import chipmunk as cp except TBB
import csfml,csfml_colors, private/components,private/common

proc debugDrawShape* (shape: cp.PShape; w: PRenderWindow){.cdecl.}=
  case shape.klass.kind
  of cp_circle_shape:
    var c {.global.} = newCircleShape(1.0, 30)
    c.setPosition shape.getBody.p.vec2f
    let r = shape.getCircleRadius
    c.setRadius r
    c.setOrigin vec2f(r,r)
    var color = white
    if shape.getSensor:
      color.a = 10
      c.setOutlineThickness 1.0
    else:
      color.a = 30
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

import fowltek/bbtree, fowltek/boundingbox, private/room_interface

proc setup (va: PVertexArray; bb: TBB) =
  va.setPrimitiveType csfml.LinesStrip
  va.resize 5
  va[0].position = vec2f(bb.left, bb.top)
  va[1].position = vec2f(bb.right,bb.top)
  va[2].position = vec2f(bb.right,bb.bottom)
  va[3].position = vec2f(bb.left,bb.bottom)
  va[4].position = vec2f(bb.left, bb.top)
proc setup (rect: PRectangleShape; bb: TBB) =
  rect.setOrigin vec2f(0,0)
  rect.setPosition vec2f(bb.left, bb.top)
  rect.setSize vec2f(bb.width, bb.height)

proc debugDraw* (W: PRenderWindow|PRenderTexture; 
                 bb: TBB; 
                 obj: PVertexArray|PRectangleShape ) =
  mixin setup
  setup obj, bb
  w.draw obj

proc debugDraw* (w: PRenderWindow; node: PBBNode[int]; drawobj: PVertexArray|PRectangleShape) =
  mixin setup
  drawObj.setup node.getBB
  w.draw drawObj
  
  if not node.isLeaf:
    w.debugDraw node.a, drawobj
    w.debugDraw node.b, drawobj

let bbtree_obj = newVertexArray()
proc debugDraw* (w: PRenderWindow; room: PRoom) =
  room.physSys.space.eachShape(
    cast[TSpaceShapeIteratorFunc](debugDrawShape), 
    cast[pointer](w)
  )
  w.debugDraw room.renderSys.tree.getRoot, bbtree_obj
