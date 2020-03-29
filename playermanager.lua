--[[

Player management

Handles new player registry and player groups.

]]--

local db = ...

local u = pmutils

--[[
Random id generator, adapted from -- --
https://gist.github.com/haggen/2fd643ea9a261fea2094#gistcomment-2339900 -- --
--                              --
Generate random hex strings as player uuids -- --
]]                              --
local charset = {}  do -- [0-9a-f]
    for c = 48, 57  do table.insert(charset, string.char(c)) end
    for c = 97, 102 do table.insert(charset, string.char(c)) end
end

function pm.random_string(length)
    if not length or length <= 0 then return '' end
    math.randomseed(os.clock()^5)
    return pm.random_string(length - 1) .. charset[math.random(1, #charset)]
end

--[[ player management proper ]]--

function pm.generate_id()
   return pm.random_string(16)
end

local QUERY_REGISTER_PLAYER = [[
  INSERT INTO player (id, name, join_date)
  VALUES (?, ?, CURRENT_TIMESTAMP)
  ON CONFLICT DO NOTHING
]]

function pm.register_player(player_name, player_id)
   return assert(u.prepare(db, QUERY_REGISTER_PLAYER, player_id, player_name))
end

local QUERY_GET_PLAYER_BY_NAME = [[
  SELECT * FROM player WHERE LOWER(player.name) = LOWER(?)
]]

function pm.get_player_by_name(player_name)
   local cur = u.prepare(db, QUERY_GET_PLAYER_BY_NAME, player_name)
   if cur then
      return cur:fetch({}, "a")
   else
      return nil
   end
end

local QUERY_GET_PLAYER_BY_ID = [[
  SELECT * FROM player WHERE player.id = ?
]]

function pm.get_player_by_id(player_id)
   local cur = u.prepare(db, QUERY_GET_PLAYER_BY_ID, player_id)
   if cur then
      return cur:fetch({}, "a")
   else
      return nil
   end
end

-- pm.register_player("Garfunel")

--[[ GROUPS ]]--

local QUERY_REGISTER_GROUP = [[
  INSERT INTO ctgroup (id, name, creation_date)
  VALUES (?, ?, CURRENT_TIMESTAMP)
  ON CONFLICT DO NOTHING
]]

function pm.register_group(ctgroup_name)
   local ctgroup_id = pm.generate_id()
   return assert(u.prepare(db, QUERY_REGISTER_GROUP, ctgroup_id, ctgroup_name))
end

local QUERY_GET_GROUP_BY_NAME = [[
  SELECT * FROM ctgroup WHERE LOWER(ctgroup.name) = LOWER(?)
]]

function pm.get_group_by_name(ctgroup_name)
   local cur = u.prepare(db, QUERY_GET_GROUP_BY_NAME, ctgroup_name)
   if cur then
      return cur:fetch({}, "a")
   else
      return nil
   end
end

local QUERY_GET_GROUP_BY_ID = [[
  SELECT * FROM ctgroup WHERE ctgroup.id = ?
]]

function pm.get_group_by_id(ctgroup_id)
   local cur = u.prepare(db, QUERY_GET_GROUP_BY_ID, ctgroup_id)
   if cur then
      return cur:fetch({}, "a")
   else
      return nil
   end
end

local QUERY_DELETE_GROUP = [[
  DELETE FROM ctgroup
  WHERE ctgroup.id = ?
]]

function pm.delete_group(ctgroup_id)
   return assert(u.prepare(db, QUERY_DELETE_GROUP, ctgroup_id))
end

local QUERY_RENAME_GROUP = [[
  UPDATE ctgroup SET name = ?
  WHERE ctgroup.id = ?
]]

function pm.rename_group(ctgroup_id, new_group_name)
   return assert(u.prepare(db, QUERY_RENAME_GROUP,
                           new_group_name, ctgroup_id))
end

--[[ PLAYER <--> GROUPS MAPPING ]]--

local QUERY_REGISTER_PLAYER_GROUP_PERMISSION = [[
  INSERT INTO player_ctgroup (player_id, ctgroup_id, permission)
  VALUES (?, ?, ?)
  ON CONFLICT DO NOTHING
]]

function pm.register_player_group_permission(player_id, ctgroup_id, permission)
   return assert(u.prepare(db, QUERY_REGISTER_PLAYER_GROUP_PERMISSION,
                         player_id, ctgroup_id, permission))
end

local QUERY_GET_PLAYER_GROUP_PERMISSION = [[
  SELECT * FROM player_ctgroup
  WHERE player_ctgroup.player_id = ?
    AND player_ctgroup.ctgroup_id = ?
]]

function pm.get_player_group(player_id, ctgroup_id)
   local cur = u.prepare(db, QUERY_GET_PLAYER_GROUP_PERMISSION,
                       player_id, ctgroup_id)
   if cur then
      return cur:fetch({}, "a")
   else
      return nil
   end
end

local QUERY_UPDATE_PLAYER_GROUP_PERMISSION = [[
  UPDATE player_ctgroup SET permission = ?
  WHERE player_ctgroup.player_id = ?
    AND player_ctgroup.ctgroup_id = ?
]]

function pm.update_player_group(player_id, ctgroup_id, permission)
   return assert(u.prepare(db, QUERY_UPDATE_PLAYER_GROUP_PERMISSION,
                         permission, player_id, ctgroup_id))
end

local QUERY_DELETE_PLAYER_GROUP = [[
  DELETE FROM player_ctgroup
  WHERE player_ctgroup.player_id = ?
    AND player_ctgroup.ctgroup_id = ?
]]

function pm.delete_player_group(player_id, ctgroup_id)
   return assert(u.prepare(db, QUERY_DELETE_PLAYER_GROUP,
                           player_id, ctgroup_id))
end

local QUERY_GET_PLAYERS_FOR_GROUP = [[
  SELECT player.id, player.name, player_ctgroup.permission
  FROM player
  INNER JOIN player_ctgroup
      ON player.id = player_ctgroup.player_id
     AND player_ctgroup.ctgroup_id = ?
]]

function pm.get_players_for_group(ctgroup_id)
   local cur = u.prepare(db, QUERY_GET_PLAYERS_FOR_GROUP, ctgroup_id)
   local players = {}
   local row = cur:fetch({}, "a")
   while row do
      -- TODO: clean up, table shallow copy helper func?
      table.insert(
         players,
         {
            name = row.name,
            id = row.id,
            permission = row.permission,
            shared_ip = row.shared_ip,
            dynamic_ip = row.dynamic_ip,
         }
      )
      row = cur:fetch(row, "a")
   end
   return players
end

local QUERY_GET_GROUPS_FOR_PLAYER = [[
  SELECT ctgroup.id, ctgroup.name, player_ctgroup.permission
  FROM ctgroup
  INNER JOIN player_ctgroup
      ON ctgroup.id = player_ctgroup.ctgroup_id
     AND player_ctgroup.player_id = ?
]]

function pm.get_groups_for_player(player_id)
   local cur = u.prepare(db, QUERY_GET_GROUPS_FOR_PLAYER, player_id)
   local groups = {}
   local row = cur:fetch({}, "a")
   while row do
      -- TODO: clean up, table shallow copy helper func?
      table.insert(
         groups,
         {
            name = row.name,
            id = row.id,
            permission = row.permission
         }
      )
      row = cur:fetch(row, "a")
   end
   return groups
end

local QUERY_DELETE_PLAYERS_FOR_GROUP = [[
  DELETE FROM player_ctgroup
  WHERE player_ctgroup.ctgroup_id = ?
]]

function pm.delete_players_for_group(ctgroup_id)
   return assert(u.prepare(db, QUERY_DELETE_PLAYERS_FOR_GROUP, ctgroup_id))
end

local QUERY_REGISTER_IPADDRESS = [[
  INSERT INTO ipaddress (value)
  VALUES (?)
  ON CONFLICT DO NOTHING
]]

function pm.register_ipaddress(ip_address)
   return assert(u.prepare(db, QUERY_REGISTER_IPADDRESS, ip_address))
end

local QUERY_REGISTER_PLAYER_IPADDRESS = [[
  INSERT INTO player_ipaddress (player_id, ip)
  VALUES (?, ?)
  ON CONFLICT DO NOTHING
]]

function pm.register_player_ipaddress(player_id, ip_address)
   return assert(u.prepare(db, QUERY_REGISTER_PLAYER_IPADDRESS,
                           player_id, ip_address))
end

local QUERY_GET_PLAYER_IPS = [[
  SELECT * FROM player_ipaddress
  WHERE player_ipaddress.player_id = ?
]]

function pm.get_player_ips(player_id)
   local cur = u.prepare(
      db, QUERY_GET_PLAYER_IPS, player_id
   )
   if not cur then return {} end

   local ips
   local row = cur:fetch({}, "a")
   while row do
      ips = ips or {}
      ips[#ips + 1] = row.ip
      row = cur:fetch(row, "a")
   end
   return ips
end

local QUERY_MATCH_PLAYER_AND_IP = [[
  SELECT * FROM player_ipaddress
  WHERE player_ipaddress.player_id = ?
    AND player_ipaddress.ip = ?
]]

function pm.match_player_and_ip(player_id, ip)
   local cur = u.prepare(
      db, QUERY_MATCH_PLAYER_AND_IP, player_id, ip
   )
   if cur then
      local row = cur:fetch({}, "a")
      return row
   end
end

local QUERY_FIND_OTHER_PLAYERS_WITH_SAME_IP = [[
  SELECT * FROM player_ipaddress
    INNER JOIN player
    ON player.id = player_ipaddress.player_id
  WHERE player_ipaddress.ip = ?
    AND player_ipaddress.player_id != ?
]]

function pm.find_other_players_with_same_ip(player_id, ip)
   local cur = u.prepare(
      db, QUERY_FIND_OTHER_PLAYERS_WITH_SAME_IP, ip, player_id
   )
   if not cur then
      return {}
   end

   local players
   local row = cur:fetch({}, "a")
   while row do
      players = players or {}
      players[#players + 1] = {
         player_name = row.name,
         shared_ip = row.shared_ip,
         dynamic_ip = row.dynamic_ip
      }
      row = cur:fetch(row, "a")
   end
   return players
end

local QUERY_SET_PLAYER_SHARED_IP = [[
  UPDATE player SET shared_ip = ? WHERE LOWER(name) = LOWER(?)
]]

function pm.set_player_shared_ip(player, ip_address)
   return assert(u.prepare(db, QUERY_SET_PLAYER_SHARED_IP, ip_address, player))
end


local QUERY_SET_PLAYER_DYNAMIC_IP = [[
  UPDATE player SET dynamic_ip = ? WHERE LOWER(name) = LOWER(?)
]]

function pm.set_player_dynamic_ip(player, ip_address)
   return assert(u.prepare(db, QUERY_SET_PLAYER_DYNAMIC_IP, ip_address, player))
end

--[[ End of DB interface ]]--
