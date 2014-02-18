import csfml
import os, re, tables, strutils
type
  PTilesheet* = ref object
    file*: string
    tex*: PTexture
    rect*: TIntRect
    rows*,cols*: int

proc create* (t: PTilesheet; row, col: int): PSprite =
  result = newSprite()
  result.setTexture t.tex, false
  var r = t.rect
  r.left = cint(col * r.width)
  r.top = cint(row * r.height)
  result.setTextureRect r 
  result.setOrigin vec2f(r.width / 2, r.height / 2)

var 
  cache = initTable[string,PTilesheet](64)
  imageFilenamePattern = re".+_(\d+)x(\d+)\.\S{3,4}"
const
  assetsDir = "assets"

proc free* (T: PTilesheet) =
  destroy t.tex

proc tilesheet* (file: string): PTilesheet =
  result = cache[file]
  if not result.isNil:
    return
  
  var img = newImage(assetsdir / file)
  
  new result, free
  result.file = file
  let sz = img.getSize
  result.tex = img.newTexture
  
  if file =~ imageFilenamePattern:
    result.rect.width = matches[0].parseInt.cint
    result.rect.height = matches[1].parseInt.cint
  result.cols = int(sz.x / result.rect.width)
  result.rows = int(sz.y / result.rect.height)
  destroy img
  cache[file] = result
