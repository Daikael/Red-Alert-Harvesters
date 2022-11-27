--[[
Mining power is 3, same as electric miner
Mining Speeds, for reference, burner is 0.35, electric is 0.5
]]--
local vehicle_speed = {"150kW", "175kW"}
local vehicle_friction = {0.045, 0.04}
local miner_health = {600, 800}
local inv_size = {50, 60}
local fuel_inv_size = {2, 3}
local animation_speed = 60
local tibdec = {-10, 10}
local tibperc = {-50, 60}
local damagetype = "laser"
if game.active_mods["Factorio-Tiberium"] then
	damagetype = "tiberium"
end

for i=1,2 do
	local vehicle_suffix = ("-type"..i)
	local suffix = (i > 1) and vehicle_suffix or ""

	local vehicle = {
		type = "car",
		name = "cncharvester"..suffix,
		icon = "__Red-Alert-Harvester__/graphics/icons/harv_icon"..suffix..".png",
		icon_size = 32,
		flags = {"placeable-neutral", "player-creation", "placeable-off-grid"},
		minable = {mining_time = 1, result = "cncharvester"..suffix},
		max_health = miner_health[i],
		corpse = "medium-remnants",
		dying_explosion = "medium-explosion",
		energy_per_hit_point = 0.5,
		resistances = {
			{
				type = "fire",
				decrease = 15,
				percent = 50
			},
			{
				type = "physical",
				decrease = 0,
				percent = 20
			},
			{
				type = "impact",
				decrease = 50,
				percent = 60
			},
			{
				type = damagetype,
				decrease = tibdec[i],
				percent = tibperc[i]
			},
		},
		selection_box = {{-2, -2.4}, {2, 2.4}},
		collision_box = {{-1.4, -1.4}, {1.4, 1.4}},
		burner =
		{
			effectivity = 1,
			fuel_inventory_size = fuel_inv_size[i],
			smoke = {
				{
					name = "tank-smoke",
					deviation = {0.25, 0.25},
					frequency = 50,
					position = {0, 1.5},
					starting_frame = 0,
					starting_frame_deviation = 60
				}
			}
		},
		minimap_representation =
		{
			filename = "__Red-Alert-Harvester__/graphics/icons/harv_icon"..suffix..".png",
			flags = {"icon"},
			size = {32, 32},
			scale = 2
		},
		equipment_grid = "cncharvester"..suffix.."-grid",
		effectivity = 2,
		--weight = 15000,
		weight = 6000,
		consumption = vehicle_speed[i],
		braking_power = vehicle_speed[i],
		terrain_friction_modifier = 0.01,
		--friction = 0.03,
		friction = vehicle_friction[i],
		rotation_speed = 0.003,
		turret_rotation_speed = 0.01,
		turret_return_timeout = 300,
		tank_driving = true,
		--guns = {"tank-machine-gun"},
		--automatic_weapon_cycling = true,
		--chain_shooting_cooldown_modifier = 0.5,
		light =
		{
			{
				intensity = 0.6,
				minimum_darkness = 0.3,
				size = 30
			},
			{
				type = "oriented",
				minimum_darkness = 0.3,
				picture =
				{
					filename = "__core__/graphics/light-cone.png",
					priority = "medium",
					scale = 2,
					width = 200,
					height = 200
				},
				shift = {0, -14},
				size = 2,
				intensity = 0.6
			}
		},
		animation =
		{
			width = 221,
			height = 185,
			frame_count = 1,
			direction_count = 64,
			shift = {0.0, -0.1875},
			scale = 0.8,
			animation_speed = 8,
			max_advance = 0.2,
			priority = "low",
			stripes =
			{
				{
					filename = "__Red-Alert-Harvester__/graphics/entity/harvester/harv-sheet"..suffix..".png",
					width_in_frames = 8,
					height_in_frames = 8,
				},
			}
		},
		stop_trigger_speed = 0.2,
		sound_no_fuel = { { filename = "__base__/sound/fight/tank-no-fuel-1.ogg", volume = 0.6 }, },
		stop_trigger =
		{
			{
				type = "play-sound",
				sound =
				{
					{
						filename = "__base__/sound/car-breaks.ogg",
						volume = 0.6
					},
				}
			},
		},
		sound_minimum_speed = 0.15;
		vehicle_impact_sound = { filename = "__base__/sound/car-metal-impact.ogg", volume = 0.65 },
		working_sound =
		{
			sound = { filename = "__base__/sound/fight/tank-engine.ogg", volume = 0.6 },
			activate_sound = { filename = "__base__/sound/fight/tank-engine-start.ogg", volume = 0.6 },
			deactivate_sound = { filename = "__base__/sound/fight/tank-engine-stop.ogg", volume = 0.6 },
			match_speed_to_activity = true,
		},
		open_sound = { filename = "__base__/sound/car-door-open.ogg", volume=0.7 },
		close_sound = { filename = "__base__/sound/car-door-close.ogg", volume = 0.7 },
		inventory_size = inv_size[i],
		track_particle_triggers = data.raw.car.tank.track_particle_triggers
	}

	data:extend{vehicle}
end