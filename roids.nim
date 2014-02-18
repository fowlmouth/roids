import private/gsm, private/sfgui, 
  private/components, private/gamedat, private/room,
  fowltek/entitty, private/gamestates,
  csfml, math, parseopt2, private/logging

randomize()
let L = newConsoleLogger(when defined(debug): lvlDebug else: lvlInfo)
logging.handlers.add L

var 
  startRoom: string
  zone = "alphazone"

for kind,key,val in getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    case key.toLower
    of "r", "room": 
      startRoom = val
  of cmdArgument:
    zone = key
    break
  else:
    #

gamedata = loadGameData(zone)
if startRoom.isNil: startRoom = gameData.firstRoom

g = newGod( videoMode(800,600,32), "roids" )
g.replace newRoomGS(startRoom)
g.run

