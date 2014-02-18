import 
  fowltek/maybe_t,
  private/common,
  json, basic2d, tables, logging


type
  PEmitterType* = ref object
    name*: string
    delay*, angle*: float
    initialImpulse*: TVector2d
    inheritVelocity*, muzzleVelocity*: float
    logic*: TMaybe[PJsonnode]
    kind*: TEmitterKind
    emits_json*: PJsonNode

  EmitterKind* {.pure.} = enum
    single,multi
  TEmitterKind* = object
    case k*: EmitterKind
    of emitterKind.single: 
      single*: PJsonNode
    of emitterKind.multi:
      multi*: seq[PEmitterType]



proc unserialize (ET: PEmitterType; J: PJsonNode) =
  if j.hasKey("delay-ms"):
    et.delay = j["delay-ms"].num.int / 1000
  elif j.hasKey("delay"):
    et.delay.getFloat j,"delay", 0.250

  withKey(j, "emits", j):  et.emitsJson = j
  
  withKey(j, "initial-impulse", j):  et.initialImpulse = vector2d(j)
  if j.hasKey"inherit-velocity":
    et.inheritVelocity = j["inherit-velocity"].toFloat
  withKey(j,"muzzle-velocity",mv):
    et.muzzleVelocity = mv.toFloat
  
  withKey(j, "logic", j): et.logic = just(j)
  
  withKey(j, "angle", j): et.angle = j.toFloat

proc emitterTy* (name: string; J: PJsonNode): PEmitterType =
  result = PEmitterType(name: name)
  result.unserialize j

proc copy* (et: PEmitterType): PEmitterType =
  template `~` (x:expr):expr = et.x
  result = PEmitterType(
    name: ~name, delay: ~delay, emitsJson: ~emitsJson, initialImpulse: ~initialImpulse,
    inheritVelocity: ~inheritVelocity, muzzleVelocity: ~muzzleVelocity,
    angle: ~angle,
    logic: ~logic)

proc settle* (et: PEmitterType; db: TTable[string, PEmitterType]) =
  case et.emitsJson.kind
  of jArray:
    et.kind = TEmitterKind()
    et.kind.k = emitterKind.multi
    et.kind.multi = newSeq[PEmitterType](et.emitsJson.len)
    for i in 0 .. < et.emitsJson.len:
      let j = et.emitsJson[i]
      let ty = db[j[0].str]
      if ty.isnil:
        warn "Did not find emitter type "& j[0].str
        continue
      et.kind.multi[i] = ty.copy
      if j.len == 2:
        et.kind.multi[i].unserialize j[1]
      
      
  of jString:
    et.kind = TEmitterKind(
      k: emitterKind.single,
      single: et.emitsJson
    )
  else:
    raise newException(EIO, "Unknown emitter kind: "& $et.emitsJson)


