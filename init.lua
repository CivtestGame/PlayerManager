
pm = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- Ensure the db object doesn't leak outside of the plugin
local db = dofile(modpath .. "/db.lua")
assert(loadfile(modpath .. "/playermanager.lua"))(db)
dofile(modpath .. "/group_commands.lua")

minetest.register_on_joinplayer(function(player)
      local pname = player:get_player_name(player)
      if not pm.get_player_by_name(pname) then
         pm.register_player(pname)
      end
end)

return pm
