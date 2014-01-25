
import private/gsm, private/sfgui, 
  private/components, private/gamedat, private/room, private/room_interface,
  fowltek/entitty, private/gamestates, private/player_data,
  csfml,csfml_colors, math, json

randomize()
gamedata = loadGamedata()
var player = loadPlayer("player.json")
g = newGod(videoMOde(800,600,32),"roids")
g.replace newRoomGS(newRoom(gameData.j["rooms"]["duel1"]))
g.run

