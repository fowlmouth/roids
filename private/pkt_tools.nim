import 
  enet,
  endians,
  unsigned
export unsigned, endians


type TScalar* = int8 | uint8 | byte | char | bool |
                int16| uint16| int32|uint32|
                float32|float64|int64|uint64


proc `>>`* [T: TScalar] (pkt:PPacket; right:var T) = 
  template data: expr = pkt.data[pkt.referenceCount].addr
  const sizeT = sizeof(T)
  when sizeT == 2:
    bigEndian16(right.addr, data)
  elif sizeT == 4:
    bigEndian32(right.addr, data)
  elif sizeT == 8:
    bigEndian64(right.addr, data)
  elif sizeT == 1:
    right = cast[ptr t](data)[]
  
  pkt.referenceCount.inc sizeof(T)

proc `>>`* (pkt:PPacket; right:var string) = 
  var len: int16
  pkt >> len
  if right.isNil: right = newString(len)
  else:           right.setLen len.int
  copyMem(right.cstring, pkt.data[pkt.referenceCount].addr, len)
  pkt.referenceCount.inc len

proc `>>`* [T:TScalar] (pkt:PPacket; right:var seq[T])=
  mixin `>>`
  var len: int16
  pkt >> len
  if right.isNil: right.newSeq len.int
  else:           right.setLen len.int
  for idx in 0 .. high(right):
    pkt >> right[idx]
proc `>>`* [T] (pkt:PPacket; right:var openarray[T]) =
  mixin `>>`
  var len: int16
  pkt >> len
  assert len.int == right.len
  for idx in 0 .. high(right):
    pkt >> right[idx]

type
  OPkt* = object
    bytes: seq[char]
    index*: int
proc initOpkt* (size = 512): OPkt =
  Opkt(
    bytes: newseq[char](size)
  )

proc data* (outp: var OPkt): ptr char = outp.bytes[outp.index].addr
proc data0* (outp: var OPkt): ptr char = outp.bytes[0].addr

proc createPacket* (O:var OPKT; flags: cint): PPacket {.inline.} =
  result = createPacket( o.data0, o.index, flags or NoAllocate.cint ) 

proc ensureSize*(pkt:var Opkt; size: int) =
  if pkt.bytes.len < pkt.index+size:
    pkt.bytes.setLen pkt.index+size

proc `<<` * [T:TScalar] (outp: var OPkt; right: T) =
  const sizeT = sizeof(T)
  outp.ensureSize sizeT
  when sizeT == 2:
    var right = right
    bigEndian16(outp.data, right.addr)
  elif sizeT == 4:
    var right = right
    bigEndian32(outp.data, right.addr)
  elif sizeT == 8:
    var right = right
    bigEndian64(outp.data, right.addr)
  elif sizeT == 1:
    data(outp)[] = cast[char](right)
  
  inc outp.index, sizeT
proc `<<` * (outp: var OPkt; right: string) =
  let strlen = right.len
  outp << strlen.int16
  outp.ensureSize strlen
  copyMem outp.data, right.cstring, strlen
  inc outp.index, strlen

proc `<<` * [T] (outp: var OPkt; right: openarray[T]) =
  mixin `<<`
  outp << right.len.int16
  outp.ensureSize right.len * sizeof(T)
  for idx in 0 .. high(right):
    outp << right[idx]

when false:
  import streams
  proc `>>`* [T: TScalar] (L: PStream; R: var T): PStream {.discardable.} =
    if L.readData(R.addr, sizeof(T)) != sizeof(T):
      raise newexception(eio, "exception message")
    L
  proc `<<`* [T: TScalar] (L: PStream; R: T): PStream {.discardable.} =
    L.write R
    L

  # length-encoded string. the length is int16
  proc `>>`* (L: PStream; R: var string): PStream {.discardable.} =
    let len = L.readInt16 
    R = L.readStr(len)
    L
  proc `<<`* (L: PStream; R: string): PStream {.discardable.} =
    L.write R.len.int16
    L.write R
    L

  # fixed-length string
  proc `>>`* [T] (L: PStream; R: var openarray[T]): PStream {.discardable.} =
    if L.readData(R[0].addr, R.len * sizeof(T)) != R.len * sizeof(T):
      raise newexception(eio,"exception message")
    L
  proc `<<`* (L: PStream; fixedString: tuple[len: int, str: string]): PStream {.discardable.}=
    if fixedString.str.len < fixedString.len:
      L.write fixedString.str
      for i in fixedString.str.len .. < fixedString.len:
        L.write '\0'
    else:
      L.write fixedString.str[0 .. fixedString.len]
    L
