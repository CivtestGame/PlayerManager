
pm = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- Ensure the db object doesn't leak outside of the plugin
local db = dofile(modpath .. "/db.lua")
assert(loadfile(modpath .. "/playermanager.lua"))(db)
dofile(modpath .. "/group_commands.lua")

minetest.register_on_joinplayer(function(player)
      local pname = player:get_player_name(player)
      local player_record = pm.get_player_by_name(pname)
      local player_id = player_record and player_record.id
      if not player_record then
         player_id = pm.generate_id()
         pm.register_player(pname, player_id)
      end

      local pinfo = minetest.get_player_information(pname)
      local ip_address = pinfo.address
      pm.register_ipaddress(ip_address)
      pm.register_player_ipaddress(player_id, ip_address)

      local other_players = pm.find_other_players_with_same_ip(
         player_id, ip_address
      )
      if other_players then
         local alts = {}
         for _,record in ipairs(other_players) do
            alts[#alts + 1] = record.player_name
         end
         minetest.log(
            pname.." ["..ip_address.."] has "..tostring(#alts)
               .." associations: ".. table.concat(alts, ", ")
         )
      end
end)

return pm
