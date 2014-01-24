import chipmunk as cp
import fowltek/idgen, fowltek/entitty, private/components
type
  PRoom* = ref object
    space*: PSpace
    ents*: seq[TEntity]
    ent_id*: TIDgen[int]
    activeEnts*: seq[int]










