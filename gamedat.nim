import fowltek/entitty, tables, json,math, components

var
  dom* = newDomain()
type
  PGameData* = var TGameData
  TGameData * = object
    entities*: TTable[string,TJent] # ent name => typeinfo and json data
    groups*: TTable[string, seq[string]] # group name => @[ ent names ]
    j*: PJsonNode 
  TJent* = tuple
    ty: PTypeinfo
    j1, j2: PJsonNode

proc randomFromGroup* (m: var TGameData; group: string): string =
  if m.groups.hasKey(group):
    let len = m.groups.mget(group).len
    return m.groups.mget(group)[random(len)]
    

proc loadGameData* (f = "ships.json"): TGameData =
  result.j = json.parseFile(f)
  result.entities = initTable[string,TJent](64) 
  result.groups = initTable[string,seq[string]](64)

  for name, x in result.j["entities"].pairs:
    var y: TJent
    var components: seq[int] = @[ ComponentInfo(Named).id ]
    for key, blah in x.pairs:
      try:
        let c = findComponent(key)
        components.add c
      except:
        discard
    
    y.ty = dom.getTypeinfo(components)
    y.j1 = %{ "Named": %name }
    y.j2 = x
    result.entities[name] = y
  for name, g in result.j["groups"].pairs:
    result.groups[name] = @[]
    for s in g:
      if result.entities.hasKey(s.str):
        result.groups.mget(name).add s.str

proc new_ent* (d: PGameData; name: string): TEntity =
  when defined(debug):
    echo "instantiating " , name
  let tj = d.entities[name]
  result = tj.ty.newEntity
  result.unserialize tj.j1
  result.unserialize tj.j2