import 
  csfml_audio, csfml,
  private/common,
  basic2d, json, os

type
  PSoundCached* = ref object
    file*: string
    buf*: csfmlAudio.PSoundBuffer
    attenuation*: float

  PSoundBuffer* = ref object
    live, dead: seq[PSound]
    checks: int
    index: int

proc loadSound* (J: PJsonNode): PSoundCached =
  var f: string
  var attenuation = 10.0
  
  if j.kind == jObject:
    f = j["file"].str
    withKey(j,"attenuation",j): attenuation = j.toFloat
  elif j.kind == jString:
    f = j.str
    
  if f.isNIL: return
  
  let b = newSoundBuffer("assets/sfx"/f)
  if b.isNIL: return
  
  new(result) do (s:PSoundCached):
    destroy s.buf
  result.file = f
  result.buf = b
  result.attenuation = attenuation

proc soundBuffer* (checksPerUpdate: int): PSoundBuffer =
  new(result) do (s: PSoundBuffer):
    for i in 0 .. high(s.live):
      s.live[i].destroy
    for i in 0 .. high(s.dead):
      s.dead[i].destroy
  
  newSeq result.live, 0
  newSeq result.dead, 0
  result.checks = checksPerUpdate

proc playSound* (sb: PSoundBuffer; sound: PSoundCached; pos: TPoint2d) =
  
  var s : PSound
  if sb.dead.len == 0:
    s = csfmlAudio.newSound()
    s.setLoop false
    s.setRelativeToListener true
    s.setAttenuation 10.0
    s.setMinDistance 350.0
    
  else:
    s = sb.dead.pop
  
  s.setPosition(vec3f(pos.x, 0, pos.y))
  s.setBuffer sound.buf
  
  s.play
  sb.live.add s

proc update* (sb: PSoundBuffer) =
  var times = 0
  while sb.index < len(sb.live) and times < sb.checks:
    if sb.live[sb.index].getStatus == Stopped:
      sb.dead.add sb.live[sb.index]
      sb.live.del sb.index
    else:
      inc sb.index
    inc times, 1
    if sb.index == len(sb.live):
      sb.index = 0
