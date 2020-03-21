
minetest.register_privilege(
   "pm_admin",
   {
      description = "Privilege to administrate PlayerManager groups."
   }
)

--[[ Command processing (eventually move framework to PMUtils) ]]--

--
-- PLEASE NOTE: the `sender` in these functions is not a player name or minetest
-- player object, but a table derived from a database record.
--
-- Its structure will be something like this:
--
-- { join_date = "2020-02-22 01:12:07.239002",
--   name = "R3",
--   id = "fff4d5ff864044ab" }
--

function pm.send_chat_group(ctgroup_id, message)
    for _, playerinfo in ipairs(pm.get_players_for_group(ctgroup_id)) do
        minetest.chat_send_player(playerinfo.name, message)
    end
end

local function matches_group_and_rank(sender, group_name, rank_spec)
   local ctgroup = pm.get_group_by_name(group_name)
   if not ctgroup then
      return nil, "Group '"..group_name.."' not found."
   end

   if minetest.check_player_privs(sender.name, { pm_admin = true }) then
      local c = minetest.colorize
      minetest.chat_send_player(
         sender.name, c("#f00", "WARNING: you have privilege: pm_admin. "
                           .. "Group actions will be forcibly applied.")
      )
      return ctgroup
   else
      local sender_group_info = pm.get_player_group(sender.id, ctgroup.id)
      if not sender_group_info then
         return nil, "You are not on the group '"..group_name.."'."
      end
      if rank_spec then
         if not next(rank_spec) then
            return nil, "Only players with privilege 'pm_admin' can use "
               .. "this command."
         elseif not rank_spec[sender_group_info.permission] then
            return nil, "You don't have permission to do that."
         end
      end
      return ctgroup
   end
end

local function group_create_cmd(sender, group_name)
   if string.len(group_name) > 16 then
      return false, "Group name '"..group_name..
         "' is too long (16 character limit)."
   end

   if pm.get_group_by_name(group_name) then
      return false, "Group '"..group_name.."' already exists."
   end

   pm.register_group(group_name)
   local ctgroup = pm.get_group_by_name(group_name)
   pm.register_player_group_permission(sender.id, ctgroup.id, "admin")

   minetest.chat_send_player(
      sender.name,
      "Group '"..group_name.."' created successfully."
   )
   return true
end

local function titlecase_word(perm)
   local head = perm:sub(1, 1)
   local tail = perm:sub(2, perm:len())
   return head:upper() .. tail:lower()
end

local function group_info_cmd(sender, group_name)
   local ctgroup, err = matches_group_and_rank(sender, group_name)
   if not ctgroup then
      return false, err
   end

   local group_players_info = pm.get_players_for_group(ctgroup.id)

   local C = minetest.colorize

   minetest.chat_send_player(
      sender.name,
      C("#0a0", "[Group: ")..C("#fff", ctgroup.name)..C("#0a0", "]") .. "\n"
         .. C("#0a0", "[Id: ")..C("#fff", ctgroup.id)..C("#0a0", "]")
   )

   -- Ugly, but I want the table keys ordered...
   local table_order_map = { admin = 1, mod = 2, member = 3 }
   local rev_table_order_map = { "admin", "mod", "member" }
   local info_lists = { {}, {}, {} }

   local function colorize_sender_name(nom)
      if sender.name == nom then
         nom = C("#f00", nom)
      end
      return nom
   end

   for _, player_info in pairs(group_players_info) do
      local permission = player_info.permission
      local info_tab_entry = table_order_map[permission]

      if not info_tab_entry then
         local rank_num = #info_lists + 1
         table_order_map[permission] = rank_num + 1
         rev_table_order_map[#rev_table_order_map + 1] = permission
         info_lists[rank_num] = {}
         table.insert(
            info_lists[rank_num], colorize_sender_name(player_info.name)
         )
      else
         local rank_idx = table_order_map[permission]
         table.insert(
            info_lists[rank_idx], colorize_sender_name(player_info.name)
         )
      end
   end

   for i, perm in ipairs(rev_table_order_map) do
      local names = info_lists[i]
      table.sort(names)
      minetest.chat_send_player(
         sender.name,
         "  " .. titlecase_word(perm) .. "s: " .. table.concat(names, ", ")
      )
   end

   return true
end

local function group_list_cmd(sender)
   local player_groups_info = pm.get_groups_for_player(sender.id)

   minetest.chat_send_player(sender.name, "Your groups:")

   local info_table = {}
   for _, group_info in pairs(player_groups_info) do
      local info_tab_entry = info_table[group_info.permission]
      if info_tab_entry then
         table.insert(info_table[group_info.permission], group_info.name)
      else
         info_table[group_info.permission] = { group_info.name }
      end
   end

   for perm, names in pairs(info_table) do
      minetest.chat_send_player(
         sender.name,
         "  " .. titlecase_word(perm) .. " of: " .. table.concat(names, ", ")
      )
   end

   return true
end

local function group_add_cmd(sender, group_name, ...)
   local ctgroup, err = matches_group_and_rank(
      sender, group_name,
      {} -- empty ranks list implies that this is server-admin only
   )
   if not ctgroup then
      return false, err
   end

   local targets = { ... }
   for _, target in ipairs(targets) do
      local target_player = pm.get_player_by_name(target)
      if not target_player then
         minetest.chat_send_player(
            sender.name,
            "Player '"..target.."' not found."
         )
         goto continue
      end

      local target_player_group_info
         = pm.get_player_group(target_player.id, ctgroup.id)
      if target_player_group_info then
         minetest.chat_send_player(
            sender.name,
            "Player '"..target_player.name ..
               "' is already on the group '"..ctgroup.name.."'."
         )
         goto continue
      end

      pm.register_player_group_permission(target_player.id, ctgroup.id, "member")

      minetest.chat_send_player(
         sender.name,
         "Player '"..target_player.name.."' added to group '" ..
            ctgroup.name .. "'."
      )
      ::continue::
   end
   return true
end

local player_invites = {}

local function invite_player_to_group(target, ctgroup)
   local target_name = target.name
   local ctgroup_name = ctgroup.name
   local ctgroup_id = ctgroup.id
   player_invites[target_name] = player_invites[target_name] or {}
   player_invites[target_name][ctgroup_id] = ctgroup
   minetest.chat_send_player(
      target_name, "You have been invited to group '"..ctgroup_name.."'. "
         .. "Use '/group accept "..ctgroup_name.."' to accept the invite."
   )
end

local function group_invite_cmd(sender, group_name, ...)
   local ctgroup, err = matches_group_and_rank(
      sender, group_name, { admin = true, mod = true }
   )
   if not ctgroup then
      return false, err
   end

   -- duplicated code from '/group add'
   local targets = { ... }
   for _, target in ipairs(targets) do
      local target_player = pm.get_player_by_name(target)
      if not target_player then
         minetest.chat_send_player(
            sender.name,
            "Player '"..target.."' not found."
         )
         goto continue
      end

      local target_player_group_info
         = pm.get_player_group(target_player.id, ctgroup.id)
      if target_player_group_info then
         minetest.chat_send_player(
            sender.name,
            "Player '"..target_player.name ..
               "' is already on the group '"..ctgroup.name.."'."
         )
         goto continue
      end

      local player_obj = minetest.get_player_by_name(target)
      if not player_obj then
         minetest.chat_send_player(
            sender.name,
            "Player '" .. target_player.name ..
               "' must be online to receive the invite."
         )
         goto continue
      end

      invite_player_to_group(target_player, ctgroup)

      minetest.chat_send_player(
         sender.name,
         "Player '"..target_player.name.."' was invited to group '" ..
            ctgroup.name .. "'."
      )
      ::continue::
   end
   return true
end

local function group_accept_cmd(sender, group_name)
   local ctgroup = pm.get_group_by_name(group_name)
   if not ctgroup then
      return nil, "Group '"..group_name.."' not found."
   end

   local sender_name = sender.name
   local ctgroup_id = ctgroup.id

   if player_invites[sender_name]
      and player_invites[sender_name][ctgroup_id]
   then
      pm.register_player_group_permission(sender.id, ctgroup_id, "member")
      player_invites[sender_name][ctgroup_id] = nil
      minetest.chat_send_player(
         sender_name, "You joined the group '"..group_name.."'."
      )
      return true
   else
      return false, "You have not been invited to group '"..group_name.."."
   end
end

local function group_remove_cmd(sender, group_name, ...)
   local ctgroup, err = matches_group_and_rank(
      sender, group_name, { admin = true }
   )
   if not ctgroup then
      return false, err
   end

   local targets = { ... }
   for _, target in ipairs(targets) do
      local target_player = pm.get_player_by_name(target)
      if not target_player then
         minetest.chat_send_player(
            sender.name,
            "Player '"..target.."' not found."
         )
         goto continue
      end

      local target_player_group_info
         = pm.get_player_group(target_player.id, ctgroup.id)
      if not target_player_group_info then
         minetest.chat_send_player(
            sender.name,
            "Player '"..target_player.name ..
               "' is not on the group '"..ctgroup.name.."'."
         )
         goto continue
      end

      pm.delete_player_group(target_player.id, ctgroup.id)

      minetest.chat_send_player(
         sender.name,
         "Player '"..target_player.name.."' removed from group '" ..
            ctgroup.name .. "'."
      )
      ::continue::
   end
   return true
end

local function group_rank_cmd(sender, group_name, target, new_target_rank)
   local ctgroup, err = matches_group_and_rank(
      sender, group_name, { admin = true }
   )
   if not ctgroup then
      return false, err
   end

   local target_player = pm.get_player_by_name(target)
   if not target_player then
      return false, "Player '"..target.."' not found."
   end

   local target_player_group_info
      = pm.get_player_group(target_player.id, ctgroup.id)
   if not target_player_group_info then
      return false, "Player '"..target_player.name ..
         "' is not on the group '"..ctgroup.name.."'."
   end
   if new_target_rank ~= "member" and
      new_target_rank ~= "mod" and
      new_target_rank ~= "admin"
   then
      return false, "Invalid permission '"..new_target_rank ..
         "', must be one of: member, mod, admin."
   end

   pm.update_player_group(target_player.id, ctgroup.id, new_target_rank)

   minetest.chat_send_player(
      sender.name,
      "Changed rank of player '"..target_player.name.."' to '" .. new_target_rank ..
         "' of group '"..ctgroup.name.."'."
   )
   return true
end

local function group_delete_cmd(sender, group_name, confirm)

   local ctgroup, err = matches_group_and_rank(
      sender, group_name, { admin = true }
   )
   if not ctgroup then
      return false, err
   end

   if not confirm or
      confirm ~= "confirm"
   then
      return false, "You must confirm this action!"
   end

   -- Deleting is a bit of a misnomer. The group stays in the database, it just
   -- has all players removed, and is renamed to something random. This frees up
   -- the name for future groups to take, but continues to allow references to
   -- the 'deleted' group.
   local newname = pm.random_string(16)
   minetest.log(
      "warning", "Deleted group "..group_name.." was renamed to "..newname.."."
   )
   pm.rename_group(ctgroup.id, newname)
   pm.delete_players_for_group(ctgroup.id)

   minetest.chat_send_player(
      sender.name,
      "Deleted group '"..ctgroup.name.."'."
   )
   return true
end

local function group_rename_cmd(sender, group_name, new_group_name)
   local ctgroup, err = matches_group_and_rank(
      sender, group_name, { admin = true }
   )
   if not ctgroup then
      return false, err
   end

   if string.len(new_group_name) > 16 then
      return false, "Proposed name '"..new_group_name..
         "' is too long (16 character limit)."
   end

   pm.rename_group(ctgroup.id, new_group_name)

   minetest.chat_send_player(
      sender.name,
      "Renamed group '"..ctgroup.name.."' to '"..new_group_name.. "'."
   )
   return true
end

local group_cmd_lookup_table = {
   create = {
      params = { "<group>" },
      fn = group_create_cmd
   },
   delete = {
      params = { "<group>", "<confirm>" },
      fn = group_delete_cmd,
      accept_many_after = 1
   },
   info = {
      params = { "<group>" },
      fn = group_info_cmd
   },
   list = {
      params = {},
      fn = group_list_cmd
   },
   rename = {
      params = { "<group>", "<new_name>" },
      fn = group_rename_cmd
   },
   add = {
      params = { "<group>", "<players...>" },
      fn = group_add_cmd,
      accept_many_after = 2
   },
   invite = {
      params = { "<group>", "<players...>" },
      fn = group_invite_cmd,
      accept_many_after = 2
   },
   accept = {
      params = { "<group>" },
      fn = group_accept_cmd,
   },
   remove = {
      params = { "<group>", "<players...>"},
      fn = group_remove_cmd,
      accept_many_after = 2
   },
   rank = {
      params = { "<group>", "<player>", "(member | mod | admin)" },
      fn = group_rank_cmd
   }
}

local u = pmutils

local function pm_parse_params(pname, raw_params, lookup_table)
   local params = {}
   for chunk in string.gmatch(raw_params, "[^%s]+") do
      table.insert(params, chunk)
   end

   if #params == 0 then
      local actions = u.table_keyvals(lookup_table)
      return false, "Usage: /group <action> ...\n" ..
         "Valid actions: " .. table.concat(actions, ", ")
   end

   -- Pop the action from the parameters
   local action = table.remove(params, 1)
   local sender = pm.get_player_by_name(pname)

   local cmd_spec = lookup_table[action]
   if cmd_spec then
      local accept_many_after = cmd_spec.accept_many_after
      local accept_many = false

      if accept_many_after then
         accept_many = true
      else
         accept_many_after = 0
      end

      if (accept_many and #params < accept_many_after)
         or (not accept_many and #params ~= #cmd_spec.params)
      then
         return false, "Invalid arguments, usage: /group " .. action .. " "
            .. table.concat(cmd_spec.params, " ")
      end
      -- all cmd handler functions take the sender, and the parameters
      return cmd_spec.fn(sender, unpack(params))
   end

   return false, "Unknown action: '"..action.."'."
end


minetest.register_chatcommand("group", {
   params = "<action> <group name> [<params...>]",
   description = "PlayerManager group management.",
   func = function(pname, params)
      local sender = minetest.get_player_by_name(pname)
      if not sender then
         return false
      end
      local success, err = pm_parse_params(
         pname, params, group_cmd_lookup_table
      )
      if not success then
         minetest.chat_send_player(pname, "Error: "..err)
         return false
      end
      return true
   end
})
