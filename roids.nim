
import private/gsm, private/sfgui, 
  private/components, private/gamedat, private/room,
  fowltek/entitty, private/gamestates,
  csfml,csfml_colors, math, json

randomize()
gamedata = loadGamedata()
g = newGod( videoMode(800,600,32), "roids" )
g.replace  newRoomGS(gameData.j["rooms"][gamedata.j["first-room"].str])
g.run

