
local function toboolean(thing)
   if type(thing) == "string" then
      thing = thing:lower()
   end
   return ((thing == "t"
               or thing == "true"
               or thing == "yes"
               or thing == "enabled"
               or thing == true) and true)
      or false
end

local assoc_enabled
   = toboolean(minetest.settings:get("playermanager_association"))

local strict_dynamic_assoc
   = toboolean(minetest.settings:get("playermanager_dynamic_strictness"))

if not assoc_enabled then
   minetest.log("warning", "[PlayerManager] Associations are DISABLED.")
else
   minetest.log("[PlayerManager] Associations are ENABLED.")
end

local function get_associations(player_record, ip)
   local other_players = pm.find_other_players_with_same_ip(
      player_record.id, ip
   )

   if other_players and next(other_players) then
      local shared_players
         = pm.get_player_shared_ip_players(player_record.id)

      local alts = {}
      for _,record in ipairs(other_players) do
         if not shared_players[record.player_name] then
            alts[#alts + 1] = record.player_name
         end
      end

      if next(alts) then
         return alts, "This IP address is already tied to account(s): "
            .. table.concat(alts, ", ") .. ". "
            .. "Multi-accounting is not allowed on Civtest. "
            .. "If you think this is an error, please contact "
            .. "a Civtest administrator on Reddit or Discord."
      end

      minetest.log(
         player_record.name.." ["..ip.."] bypassed alt check [shared IP with "
            .. table.concat(alts, ", ") .. "]."
      )
   end
end

minetest.register_on_joinplayer(function(player)
      -- Handle new players. We have to register new players at this point,
      -- since this is the only post-authentication join handler. Newbies get
      -- alt-association checked again, since we now have them in the db.
      --
      -- We don't log their IP if they fail the check -- doing so would only
      -- complicate the job of detangling the alt/IP combos.
      --
      local name = player:get_player_name()
      local pinfo = minetest.get_player_information(name)
      local ip = pinfo.address
      local player_record = pm.get_player_by_name(name)
      local player_id = player_record and player_record.id
      if not player_record then
         player_id = pm.generate_id()
         pm.register_player(name, player_id)

         if not assoc_enabled then
            return
         end

         player_record = pm.get_player_by_name(name)
         local alts, msg = get_associations(player_record, ip)
         if alts then
            if combat_tag then
               -- Remove the combat tag so the player doesn't die on kick.
               -- Specifically, we make them exempt.
               combat_tag.make_exempt(player)
            end
            minetest.kick_player(name, msg)
            return
         end
      end

      pm.register_ipaddress(ip)
      pm.register_player_ipaddress(player_id, ip)
end)


minetest.register_on_prejoinplayer(function(name, ip)
      if not assoc_enabled then
         return
      end

      if name:len() >= 20 then
         -- I think MT protects us against this, but who knows.
         return "Username: '"..name.."' is too long."
      end

      local player_record = pm.get_player_by_name(name)
      if not player_record then
         -- New player joined. We handle their IP associations in
         -- register_on_joinplayer, since this client has not yet authenticated.
         return
      end

      local player_dynamic_ip = toboolean(player_record.dynamic_ip)
      if player_dynamic_ip then
         -- If a player designated as having a dynamic IP ends up on the same
         -- network as a pre-existing player, well, that's weird. It'll be
         -- logged anyway.
         minetest.log(
            name.." ["..ip.."] bypassed IP check [dynamic IP address]."
         )
         return
      end

      -- Existing accounts with associations are not allowed to connect.
      local alts, msg = get_associations(player_record, ip)
      if alts then
         return msg
      end

      -- Unless the player is specifed as having a shared or dynamic IP, they
      -- should only be able connect from their designated, static IP.
      --
      -- This can be turned off with the playermanager_dynamic_strictness config

      if not strict_dynamic_assoc then
         return
      end

      local player_id = player_record.id
      local ip_match = pm.match_player_and_ip(player_id, ip)
      if not ip_match then
         local ips = pm.get_player_ips(player_id)
         if not ips or not next(ips) then
            minetest.log(
               name.." ["..ip.."] did not have an IP address assigned."
            )
            return
         end

         minetest.log(
            name.." ["..ip.."] tried to log in with unauthorised IP. "
               .. "(Authorised: " .. table.concat(ips, ", ") ..")"
         )
         return "This account is tied to a different IP address. "
            .. "If your connection circumstances have changed, please "
            .. "contact a Civtest administrator on Reddit or Discord."
      end
end)

minetest.register_chatcommand(
   "assoc_shared",
   {
      params = "<player1> <player2>",
      description = "Allow two players to share their IP addresses.",
      privs = { pm_admin = true },
      func = function(name, param)
         local split = param:split(" ")
         if not next(split) or not split[1] then
            return false, "No player1 specified."
         end
         local player1 = split[1]
         if not split[2] then
            return false, "No player2 specified."
         end
         local player2 = split[2]

         local player1_record = pm.get_player_by_name(player1)
         if not player1_record then
            return false, "Player '"..player1.."' not found."
         end

         local player2_record = pm.get_player_by_name(player2)
         if not player2_record then
            return false, "Player '"..player2.."' not found."
         end

         local player1_id = player1_record.id
         local player2_id = player2_record.id

         -- Build the two-way association
         pm.set_player_new_shared_ip(player1_id, player2_id)
         pm.set_player_new_shared_ip(player2_id, player1_id)

         minetest.chat_send_player(
            name, "Success: " .. player1 .. " and " .. player2 .. " "
               .. "can now share their connection."
         )
      end
   }
)

minetest.register_chatcommand(
   "assoc_dynamic",
   {
      params = "<player> <t|f>",
      description = "Designate a player as having a dynamic IP.",
      privs = { pm_admin = true },
      func = function(name, param)
         local split = param:split(" ")
         if not next(split) or not split[1] then
            return false, "No target specified."
         end
         local target = split[1]
         if not split[2] then
            return false, "No value specified."
         end
         local val = split[2]

         if val == "t" then
            val = true
         elseif val == "f" then
            val = false
         else
            return false, "Value is not 't' or 'f'."
         end

         local player_record = pm.get_player_by_name(target)
         if player_record then
            pm.set_player_dynamic_ip(target, val)
            minetest.chat_send_player(
               name, "Dynamic IP updated for '"..target.."'."
            )
         else
            return false, "Player '"..target.."' not found."
         end

      end
   }
)

minetest.register_chatcommand(
   "assoc_info",
   {
      params = "<player>",
      description = "Show player association info.",
      privs = { pm_admin = true },
      func = function(name, param)
         if param == "" then
            return false, "No player specified."
         end
         local target = param

         local player_record = pm.get_player_by_name(target)

         if not player_record then
            return false, "Player '"..target.."' was not found."
         end

         local dynamic_ip = (player_record.dynamic_ip == "t" and "YES")
            or "NO"

         local ips = pm.get_player_ips(player_record.id)

         local alts = {}

         for _,ip in ipairs(ips) do
            local other_players = pm.find_other_players_with_same_ip(
               player_record.id, ip
            ) or {}

            for _,record in ipairs(other_players) do
               local item = record.player_name
               alts[#alts + 1] = item
            end
         end

         local online_and_ip = ""
         if minetest.get_player_by_name(player_record.name) then
            local pinfo = minetest.get_player_information(player_record.name)
            online_and_ip = "  Player is ONLINE: " .. pinfo.address
         end

         local _,shared_with = pm.get_player_shared_ip_players(player_record.id)

         minetest.chat_send_player(
            name,
            "Player: "..player_record.name.." [ "..player_record.id.." ]\n"
               .."  Associations: "..table.concat(alts, ", ").."\n"
               .."  Shares IP with: " .. table.concat(shared_with, ", ") .. "\n"
               .."  Dynamic IP: "..dynamic_ip.."\n"
               .."  IPs: "..table.concat(ips, ", ").."\n"
               ..online_and_ip
         )
      end
   }
)
