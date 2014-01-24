import fowltek/entitty, tables, json,math, 
  private/components

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

proc safeFindComponent* (n:string): int =
  try:
    result = findComponent(n)
  except:
    result = -1

proc loadGameData* (f = "ships.json"): TGameData =
  result.j = json.parseFile(f)
  result.entities = initTable[string,TJent](64) 
  result.groups = initTable[string,seq[string]](64)

  template maybeAdd (seq; c): stmt =
    if(;let id = safeFindComponent(c); id != -1):
      seq.add id

  var defaultComponents: seq[int] = @[]
  if result.j.hasKey("required-components"):
    for c in result.j["required-components"]:
      defaultComponents.maybeAdd c.str

  for name, x in result.j["entities"].pairs:
    var comps = defaultComponents
    for key, blah in x.pairs:
      comps.maybeAdd key
    if x.hasKey("Components"):
      for c in x["Components"]:
        comps.maybeAdd c.str

    var y: TJent
    y.ty = dom.getTypeinfo(comps)
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
  let tj = d.entities.mget(name).addr
  result = tj.ty.newEntity
  result.unserialize tj.j1
  result.unserialize tj.j2

proc new_ent* (d: PGameData; name: PJsonNode): TEntity =
  if name.kind == jArray:
    if name[0].kind == jString and name[0].str == "group":
      return d.new_ent(d.random_from_group(name[1].str))
  elif name.kind == jString:
    return d.new_ent(name.str)


