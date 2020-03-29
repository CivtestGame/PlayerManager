
pm = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- Ensure the db object doesn't leak outside of the plugin
local db = dofile(modpath .. "/db.lua")
assert(loadfile(modpath .. "/playermanager.lua"))(db)
dofile(modpath .. "/group_commands.lua")
dofile(modpath .. "/associations.lua")

return pm
