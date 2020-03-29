
minetest.register_on_prejoinplayer(function(name, ip)
      if name:len() >= 20 then
         -- I think MT protects us against this, but who knows
         return "Username: '"..name.."' is too long."
      end

      local player_record = pm.get_player_by_name(name)
      local player_id = player_record and player_record.id

      -- Step 1: if a player hasn't yet registered, register them and log their
      -- IP address.
      if not player_record then
         player_id = pm.generate_id()
         pm.register_player(name, player_id)
         pm.register_ipaddress(ip)
         pm.register_player_ipaddress(player_id, ip)

         player_record = pm.get_player_by_name(name)
      end

      local other_players = pm.find_other_players_with_same_ip(
         player_id, ip
      )

      if other_players and next(other_players) then
         local player_shared_ip = player_record.shared_ip

         local alts = {}
         for _,record in ipairs(other_players) do
            if not record.shared_ip
               or not player_shared_ip
               or record.shared_ip ~= player_shared_ip
            then
               alts[#alts + 1] = record.player_name
            end
         end

         if next(alts) then
            minetest.log(
               name.." ["..ip.."] tried to log in, but has "
                  ..tostring(#alts).." associations: "..table.concat(alts, ", ")
            )
            return "This IP address is already tied to account(s): "
               .. table.concat(alts, ", ") .. ". "
               .. "Multi-accounting is not allowed on Civtest. "
               .. "If you think this is an error, please contact "
               .. "a Civtest administrator on Reddit or Discord."
         end

         minetest.log(
            name.." ["..ip.."] bypassed alt check [shared IP address: "
               .. table.concat(alts, ", ") .. "]."
         )
      end

      local player_dynamic_ip = player_record.dynamic_ip
      -- db spits out booleans as "t" and "f"
      player_dynamic_ip = ((player_dynamic_ip == "t") and true) or false

      if player_dynamic_ip then
         minetest.log(
            name.." ["..ip.."] bypassed IP check [dynamic IP address]."
         )
         pm.register_ipaddress(ip)
         pm.register_player_ipaddress(player_id, ip)
         return
      end

      local ip_match = pm.match_player_and_ip(player_id, ip)

      if not ip_match then
         local ips, shared = pm.get_player_ips(player_id)
         if not ips then
            pm.register_ipaddress(ip)
            pm.register_player_ipaddress(player_id, ip)
            minetest.log(
               name.." ["..ip.."] did not have an IP address assigned. "
               .. "Using the latest one..."
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
