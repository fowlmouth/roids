import private/gsm, 
  private/components, private/gamedat, private/room,
  private/gamestates,
  csfml, math, parseopt2, os, private/logging

randomize()
let L = newConsoleLogger(when defined(debug): lvlDebug else: lvlInfo)
logging.handlers.add L

var 
  startRoom: string
  zone: string

for kind,key,val in getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    case key.toLower
    of "r", "room": 
      startRoom = val
    of "z","zone":
      zone = val
  of cmdArgument:
    #zone = key
    break
  else:
    discard

g = newGod( videoMode(800,600,32),"Roids" )

if zone.isNil:
  g.replace lobbyState()

else:

  let gamedata = loadGameData("data" / zone)
  if startRoom.isNil: startRoom = gameData.firstRoom

  g.replace newRoomGS(gameData, startRoom)
  
g.run

