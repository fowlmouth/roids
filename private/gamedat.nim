import entoody, tables, json,math, os,
  private/components, private/common, private/room_interface,
  private/emitter_type, private/soundbuffer,
  basic2d,
  fowltek/maybe_t

var
  dom* = newDomain()

proc randomFromGroup* (m: PGameData; group: string): string =
  if m.groups.hasKey(group):
    let len = m.groups.mget(group).len
    return m.groups.mget(group)[random(len)]

proc safeFindComponent* (n:string): int =
  try:
    result = findComponent(n)
  except:
    result = -1


let defaultComponents = components(RCC, Named)

proc loadGameData* (dir: string): PGameData =
  if not dirExists(dir):
    raise newException(EBase,"Missing directory "& dir)
  
  result = PGameData()
  result.j = json.parseFile(dir/"zone.json")
  result.dir = dir
  result.entities = initTable[string,TJent](64)
  result.groups = initTable[string,seq[string]](64)
  result.rooms = initTable[string,PJsonNode](64)
  result.emitters = initTable[string,PEmitterType](64)
  result.sounds = initTable[string,PSoundCached](64)
  result.soundBuf = soundBuffer(10)

  template maybeAdd (seq; c): stmt =
    if(;let id = safeFindComponent(c); id != -1):
      when defined(debug): echo "Component ", c
      seq.add id

  for r in walkFiles(dir/"rooms/*.json"):
    let
      j = json.parseFile(r)
    var
      room_name = r.extractFilename.changeFileExt("")
    
    if not j.hasKey("name"):
      j["name"] = %room_name
    else:
      room_name = j["name"].str
    
    result.rooms[room_name] = j

  
  if result.j.hasKey"first-room":
    result.firstRoom = result.j["first-room"].str
  else:
    for r, whocares in result.rooms:
      result.firstRoom = r
      break

  for name, x in json.parseFile(dir/"emitters.json").pairs:
    let em = emitterTy(name, x)
    result.emitters[em.name] = em
  for key in result.emitters.keys:
    result.emitters[key].settle result.emitters

  proc importEntities (result: PGameData; file: string; namespace: string) =
    let namespace = if namespace.isNIL: "" else: namespace & "."
    
    for name, x in json.parseFile(file).pairs:
      var comps = defaultComponents
      for key, blah in x.pairs:
        comps.maybeAdd key
      if x.hasKey("Components"):
        for c in x["Components"]:
          comps.maybeAdd c.str

      let ent_name = namespace & name
      
      var y: TJent
      y.ty = dom.getTypeinfo(comps)
      y.j1 = %{ "Named": %ent_name }
      y.j2 = x
      result.entities[ent_name] = y
  
  if fileExists( dir / "entities.json" ):
    importEntities result, dir/"entities.json", nil
  if dirExists ( dir / "entities" ):
    for file in walkFiles(dir / "entities/*.json"):
      importEntities result, file, file.splitFile.name
  
  for name, g in result.j["groups"].pairs:
    result.groups[name] = @[]
    for s in g:
      if result.entities.hasKey(s.str):
        result.groups.mget(name).add s.str



