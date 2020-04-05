
pm = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())

local ie = minetest.request_insecure_environment() or
   error("PlayerManager needs to be a trusted mod. "
            .."Add it to `secure.trusted_mods` in minetest.conf")

-- Ensure the db object doesn't leak outside of the plugin
local db = loadfile(modpath .. "/db.lua")(ie)
assert(loadfile(modpath .. "/playermanager.lua"))(db)
dofile(modpath .. "/group_commands.lua")
dofile(modpath .. "/associations.lua")

return pm
