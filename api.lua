local mod = {
	player_physics = type(core.modify_physics) == "function",
}

--[[-----------------------------------------------------------------------------------------------------------]]--
if not mod.player_physics then
-- Store each player's base/original physics values.
local base_physics = {}

-- Tracks cumulative delta adjustments for each player.
local cumulative_deltas = {}

-- Each player's active override contributions (as a stack of effect entries).
local active_overrides = {}

-- Initialize physics tracking for a player.
function core.init_physics_tracking(player)
    local name = player:get_player_name()
    if not base_physics[name] then
        local def = player:get_physics_override()
        base_physics[name] = { speed = def.speed, jump = def.jump, gravity = def.gravity }
        cumulative_deltas[name] = { speed = 0, jump = 0, gravity = 0 }
    end
end

-- Composite calculation: blending base physics, delta adjustments, and active overrides.
local function compute_composite_override(name)
    local base = base_physics[name]
    local deltas = cumulative_deltas[name]
    local composite = {
        speed   = base.speed   + deltas.speed,
        jump    = base.jump    + deltas.jump,
        gravity = base.gravity + deltas.gravity,
    }
    if active_overrides[name] and #active_overrides[name] > 0 then
        local sum = { speed = 0, jump = 0, gravity = 0 }
        local totalWeight = { speed = 0, jump = 0, gravity = 0 }
        for _, entry in ipairs(active_overrides[name]) do
            local over = entry.override
            local weight = entry.weight or 1
            if over.speed then
                sum.speed = sum.speed + over.speed * weight
                totalWeight.speed = totalWeight.speed + weight
            end
            if over.jump then
                sum.jump = sum.jump + over.jump * weight
                totalWeight.jump = totalWeight.jump + weight
            end
            if over.gravity then
                sum.gravity = sum.gravity + over.gravity * weight
                totalWeight.gravity = totalWeight.gravity + weight
            end
        end
        if totalWeight.speed > 0 then
            composite.speed = composite.speed + (sum.speed / totalWeight.speed)
        end
        if totalWeight.jump > 0 then
            composite.jump = composite.jump + (sum.jump / totalWeight.jump)
        end
        if totalWeight.gravity > 0 then
            composite.gravity = composite.gravity + (sum.gravity / totalWeight.gravity)
        end
    end
    return composite
end

-- Modifies physics using delta adjustments.
function core.modify_physics(player, delta)
    local name = player:get_player_name()
    core.init_physics_tracking(player)
    delta.speed   = delta.speed   or 0
    delta.jump    = delta.jump    or 0
    delta.gravity = delta.gravity or 0
    cumulative_deltas[name].speed   = cumulative_deltas[name].speed   + delta.speed
    cumulative_deltas[name].jump    = cumulative_deltas[name].jump    + delta.jump
    cumulative_deltas[name].gravity = cumulative_deltas[name].gravity + delta.gravity
    local new_override = compute_composite_override(name)
    player:set_physics_override(new_override)
    return { delta = delta, new_override = new_override }
end

-- Applies a new override contribution from a mod.
function core.apply_override(player, override, modID, weight)
    local name = player:get_player_name()
    core.init_physics_tracking(player)
    if type(override) ~= "table" then
        override = core.default_suppressed
    end
    if not active_overrides[name] then
        active_overrides[name] = {}
    end
    table.insert(active_overrides[name], { id = modID, override = override, weight = weight or 1 })
    local new_override = compute_composite_override(name)
    player:set_physics_override(new_override)
end

-- Removes a specific override contribution.
function core.remove_override(player, modID)
    local name = player:get_player_name()
    if not active_overrides[name] then return end
    for i = #active_overrides[name], 1, -1 do
        if active_overrides[name][i].id == modID then
            table.remove(active_overrides[name], i)
            break
        end
    end
    local new_override = compute_composite_override(name)
    player:set_physics_override(new_override)
end
end

local function get_node_definition(player, altPos)
	local position = altPos or player:get_pos()
	local nodeBelow = core.get_node_or_nil(position)
	if nodeBelow then
		local nodeDefinition = core.registered_nodes[nodeBelow.name]
		if nodeDefinition then
			return nodeDefinition
		end
	end
	return nil
end
hangglider = {
	translator = minetest.get_translator('hangglider'),
}
local S = hangglider.translator

local has_player_monoids = minetest.get_modpath("player_monoids")
local has_pova = minetest.get_modpath("pova")
local has_areas = minetest.get_modpath("areas")

local enable_hud_overlay = minetest.settings:get_bool("hangglider.enable_hud_overlay", true)
local enable_flak = has_areas and minetest.settings:get_bool("hangglider.enable_flak", true)
local flak_warning_time = tonumber(minetest.settings:get("hangglider.flak_warning_time")) or 2
local hangglider_uses = tonumber(minetest.settings:get("hangglider.uses")) or 250

local flak_warning = S("You have entered restricted airspace!@n"
	.. "You will be shot down in @1 seconds by anti-aircraft guns!",
	flak_warning_time)

local hanggliding_players = {}
local hud_overlay_ids = {}

if enable_flak then
	minetest.register_chatcommand("area_flak", {
		params = S("<ID>"),
		description = S("Toggle airspace restrictions for area <ID>."),
		func = function(name, param)
			local id = tonumber(param)
			if not id then
				return false, S("Invalid usage, see /help area_flak.")
			end
			if not areas:isAreaOwner(id, name) then
				return false, S("Area @1 does not exist or is not owned by you.", id)
			end
			local open = not areas.areas[id].flak
			-- Save false as nil to avoid inflating the DB.
			areas.areas[id].flak = open or nil
			areas:save()
			return true, S("Area @1 airspace is @2.", id,
				open and S("closed") or S("opened"))
		end
	})
end

local function set_hud_overlay(player, name, show)
	if not enable_hud_overlay then
		return
	end
	if not hud_overlay_ids[name] and show == true then
		hud_overlay_ids[name] = player:hud_add({
			hud_elem_type = "image",
			text = "hangglider_overlay.png",
			position = {x = 0, y = 0},
			scale = {x = -100, y = -100},
			alignment = {x = 1, y = 1},
			offset = {x = 0, y = 0},
			z_index = -150
		})
	elseif hud_overlay_ids[name] and show == false then
		player:hud_remove(hud_overlay_ids[name])
		hud_overlay_ids[name] = nil
	end
end

local function set_physics_overrides(player, overrides)
	if has_player_monoids then
		for name, value in pairs(overrides) do
			player_monoids[name]:add_change(player, value, "hangglider:glider")
		end
	elseif has_pova then
		pova.add_override(player:get_player_name(), "hangglider:glider",
				{jump = 0, speed = overrides.speed, gravity = overrides.gravity})
		pova.do_override(player)
	else
		core.apply_override(player, overrides, "hangglider:gliding")
	end
end

local function remove_physics_overrides(player)
	if has_player_monoids then
		for _, name in pairs({"jump", "speed", "gravity"}) do
			player_monoids[name]:del_change(player, "hangglider:glider")
		end
	elseif has_pova then
		pova.del_override(player:get_player_name(), "hangglider:glider")
		pova.do_override(player)
	else
		core.remove_override(player, "hangglider:gliding")
	end
end

local function can_fly(pos, name)
	if not enable_flak then
		return true
	end
	local flak = false
	local owners = {}
	for _, area in pairs(areas:getAreasAtPos(pos)) do
		if area.flak then
			flak = true
		end
		owners[area.owner] = true
	end
	if flak and not owners[name] then
		return false
	end
	return true
end

local function safe_node_below(pos)
	local node = minetest.get_node_or_nil(vector.new(pos.x, pos.y - 0.5, pos.z))
	if not node then
		return false
	end
	local def = minetest.registered_nodes[node.name]
	if def and (def.walkable or (def.liquidtype ~= "none" and def.damage_per_second <= 0)) then
		return true
	end
	return false
end

local function shoot_flak_sound(pos)
	minetest.sound_play("hangglider_flak_shot", {
		pos = pos,
		max_hear_distance = 30,
		gain = 10.0,
	}, true)
end

local function hangglider_step(self, dtime)
	local gliding = false
	local player = self.object:get_attach("parent")
	if player then
		local pos = player:get_pos()
		local name = player:get_player_name()
		if hanggliding_players[name] then
			if not safe_node_below(pos) then
				gliding = true
				local vel = player:get_velocity().y
				if vel < 0 and vel > -3 then
					set_physics_overrides(player, {
						speed = math.abs(vel / 2.0) + 1.0,
						gravity = (vel + 3) / 20,
					})
				elseif vel <= -3 then
					set_physics_overrides(player, {
						speed = 2.5,
						gravity = -0.1,
					})
					if vel < -5 then
						-- Extra airbrake when falling too fast
						player:add_velocity(vector.new(0, math.min(5, math.abs(vel / 10.0)), 0))
					end
				else  -- vel > 0
					set_physics_overrides(player, {
						speed = 1.0,
						gravity = 0.25,
					})
				end
			end
			if not can_fly(pos, name) then
				if not self.flak_timer then
					self.flak_timer = 0
					shoot_flak_sound(pos)
					minetest.chat_send_player(name, flak_warning)
				else
					self.flak_timer = self.flak_timer + dtime
				end
				if self.flak_timer > flak_warning_time then
					player:set_hp(1, {type = "set_hp", cause = "hangglider:flak"})
					player:get_inventory():remove_item("main", ItemStack("hangglider:hangglider"))
					shoot_flak_sound(pos)
					gliding = false
				end
			end
			if not gliding then
				remove_physics_overrides(player)
				hanggliding_players[name] = nil
				set_hud_overlay(player, name, false)
			end
		end
	end
	if not gliding then
		self.object:set_detach()
		self.object:remove()
	end
end

local function hangglider_use(stack, player)
	if type(player) ~= "userdata" then
		return  -- Real players only
	end
	local pos = player:get_pos()
	local name = player:get_player_name()
	if not hanggliding_players[name] then
		minetest.sound_play("hanggliger_equip", {pos = pos, max_hear_distance = 8, gain = 1.0}, true)
		local entity = minetest.add_entity(pos, "hangglider:glider")
		if entity then
			entity:set_attach(player, "", vector.new(0, 10, 0), vector.new(0, 0, 0))
			local color = stack:get_meta():get("hangglider_color")
			if color then
				entity:set_properties({
					textures = {"wool_white.png^[multiply:#"..color, "default_wood.png"}
				})
			end
			set_hud_overlay(player, name, true)
			set_physics_overrides(player, {jump = 0, gravity = 0.25})
			hanggliding_players[name] = true
			if hangglider_uses > 0 then
				stack:add_wear(65535 / hangglider_uses)
			end
			return stack
		end
	else
		set_hud_overlay(player, name, false)
		remove_physics_overrides(player)
		hanggliding_players[name] = nil
	end
end

minetest.register_on_dieplayer(function(player)
	local name = player:get_player_name()
	hanggliding_players[name] = nil
	remove_physics_overrides(player)
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	hanggliding_players[name] = nil
	hud_overlay_ids[name] = nil
	remove_physics_overrides(player)
end)

minetest.register_on_player_hpchange(function(player, hp_change, reason)
	local name = player:get_player_name()
	if hanggliding_players[name] and reason.type == "fall" then
		-- Stop all fall damage when hanggliding
		return 0, true
	end
	return hp_change
end, true)

minetest.register_entity("hangglider:glider", {
	visual = "mesh",
	visual_size = {x = 12, y = 12},
	collisionbox = {0,0,0,0,0,0},
	mesh = "hangglider.obj",
	immortal = true,
	static_save = false,
	textures = {"wool_white.png", "default_wood.png"},
	on_step = hangglider_step,
})

minetest.register_tool("hangglider:hangglider", {
	description = S("Glider"),
	inventory_image = "hangglider_item.png",
	sound = {breaks = "default_tool_breaks"},
	on_use = hangglider_use,
})

dofile(minetest.get_modpath("hangglider").."/crafts.lua")
