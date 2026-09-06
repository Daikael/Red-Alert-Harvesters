-- Slave mining-drill. Cars cannot host module_slots; this entity can.
-- 2.1.12: the drill actually mines so Factorio applies productivity / efficiency /
-- speed natively. A hidden pole + electric-energy-interface form a private
-- micro-grid (powered from the hybrid pool in control). A hopper catches output.

local function bay_animation()
	local frame = {
		filename = "__Red-Alert-Harvesters__/graphics/icons/harv_icon.png",
		width = 32,
		height = 32,
		scale = 0.45,
		shift = {0.85, 0.85},
		frame_count = 1,
		priority = "extra-high"
	}
	return {
		north = {layers = {frame}},
		east = {layers = {frame}},
		south = {layers = {frame}},
		west = {layers = {frame}}
	}
end

local HIDDEN_FLAGS = {
	"placeable-off-grid",
	"not-on-map",
	"not-blueprintable",
	"not-deconstructable",
	"not-repairable",
	"not-flammable",
	"hide-alt-info",
	"no-automated-item-removal",
	"no-automated-item-insertion"
}

-- Baseline matches 2.1.11 no-module cadence:
--   Ore 1.5/s × 120 kJ = 180 kW
--   Tiberium 3.0/s × 120 kJ = 360 kW
-- Native modules then change rate and draw (prod bonus, efficiency, speed).
local function module_bay(name, slots, icon, mining_speed, energy_usage, search_radius)
	return {
		type = "mining-drill",
		name = name,
		icon = icon,
		icon_size = 32,
		-- Visible enough to open (SHIFT+E / click hitch) so the energy bar shows.
		hidden = false,
		hidden_in_factoriopedia = true,
		flags = {
			"placeable-off-grid",
			"not-on-map",
			"not-blueprintable",
			"not-deconstructable",
			"not-repairable",
			"not-flammable",
			"no-automated-item-removal",
			"no-automated-item-insertion"
		},
		max_health = 1,
		collision_box = {{-0.15, -0.15}, {0.15, 0.15}},
		collision_mask = {layers = {}},
		selection_box = {{-0.4, -0.4}, {0.4, 0.4}},
		selectable_in_game = true,
		minable = nil,
		-- Vanilla only. Do not list basic-solid-tiberium here: that
		-- resource-category exists only when Factorio-Tiberium is loaded
		-- (boot error assignID on Deck without that mod). Type-2 gets real
		-- Tiberium categories in data-final-fixes.lua when they exist.
		resource_categories = {"basic-solid"},
		resource_searching_radius = search_radius,
		quality_affects_mining_radius = false,
		vector_to_place_result = {0, 0},
		mining_speed = mining_speed,
		energy_usage = energy_usage,
		energy_source = {
			type = "electric",
			usage_priority = "secondary-input",
			emissions_per_minute = {pollution = 10},
			drain = "0W",
			buffer_capacity = "400kJ",
			input_flow_limit = "5MW",
			output_flow_limit = "0W",
			render_no_power_icon = false,
			render_no_network_icon = false
		},
		module_slots = slots,
		quality_affects_module_slots = false,
		allowed_effects = {"speed", "productivity", "consumption", "pollution", "quality"},
		graphics_set = {
			animation = bay_animation()
		}
	}
end

data:extend({
	module_bay(
		"cncharvester-module-bay",
		2,
		"__Red-Alert-Harvesters__/graphics/icons/harv_icon.png",
		1.5,
		"180kW",
		2.5
	),
	module_bay(
		"cncharvester-type2-module-bay",
		3,
		"__Red-Alert-Harvesters__/graphics/icons/harv_icon-type2.png",
		3.0,
		"360kW",
		3.5
	),
})

-- Invisible 256×256 sheet already in the pack. Scale ~0 so the hitch
-- micro-grid (pole / EEI / hopper) does not paint moving tiles.
local TRANSPARENT = "__Red-Alert-Harvesters__/graphics/entity/transparent.png"

local function invisible_sprite(extra)
	local sprite = {
		filename = TRANSPARENT,
		width = 256,
		height = 256,
		scale = 0.001,
		priority = "very-low",
		flags = {"no-crop"}
	}
	if extra then
		for key, value in pairs(extra) do
			sprite[key] = value
		end
	end
	return sprite
end

local function invisible_4way()
	local frame = invisible_sprite()
	return {
		north = frame,
		east = frame,
		south = frame,
		west = frame
	}
end

local function strip_world_graphics(ent)
	ent.pictures = nil
	ent.picture = invisible_sprite()
	ent.animation = nil
	ent.animations = nil
	ent.idle_animation = nil
	ent.working_visualisations = nil
	ent.graphics_set = nil
	ent.light = nil
	ent.light1 = nil
	ent.light2 = nil
	ent.light_when_powered = nil
	ent.water_reflection = nil
	ent.radius_visualisation_picture = invisible_sprite()
	ent.integration_patch = nil
	ent.circuit_connector = nil
	ent.circuit_connector_sprites = nil
	ent.corpse = nil
	ent.dying_explosion = nil
	ent.damaged_trigger_effect = nil
	ent.alert_icon_scale = 0
	ent.draw_copper_wires = false
	ent.draw_circuit_wires = false
	ent.selectable_in_game = false
	ent.selection_box = {{0, 0}, {0, 0}}
	ent.hidden = true
	ent.hidden_in_factoriopedia = true
	ent.flags = HIDDEN_FLAGS
end

-- Private pole: supply_area covers the slaved drill; wire distance 0 so it
-- never joins the factory copper grid (that would dump hybrid power out).
local pole = table.deepcopy(data.raw["electric-pole"]["small-electric-pole"])
pole.name = "cncharvester-drill-pole"
pole.icon = "__Red-Alert-Harvesters__/graphics/icons/harv_icon.png"
pole.icon_size = 32
pole.minable = nil
pole.max_health = 1
pole.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
pole.collision_mask = {layers = {}}
pole.maximum_wire_distance = 0
pole.supply_area_distance = 1
pole.next_upgrade = nil
pole.fast_replaceable_group = nil
pole.placeable_by = nil
strip_world_graphics(pole)
-- ElectricPolePrototype requires pictures (not picture).
pole.pictures = {
	layers = {
		invisible_sprite{direction_count = 4}
	}
}
pole.connection_points = pole.connection_points or {
	{
		shadow = {copper = {0, 0}},
		wire = {copper = {0, 0}}
	}
}
data:extend({pole})

local supply = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
supply.name = "cncharvester-drill-supply"
supply.icon = "__Red-Alert-Harvesters__/graphics/icons/harv_icon.png"
supply.icon_size = 32
supply.minable = nil
supply.max_health = 1
supply.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
supply.collision_mask = {layers = {}}
supply.gui_mode = "none"
supply.allow_copy_paste = false
supply.continuous_animation = false
supply.energy_production = "0W"
supply.energy_usage = "0W"
supply.energy_source = {
	type = "electric",
	buffer_capacity = "2MJ",
	usage_priority = "primary-output",
	input_flow_limit = "0W",
	output_flow_limit = "5MW",
	render_no_power_icon = false,
	render_no_network_icon = false
}
supply.next_upgrade = nil
supply.placeable_by = nil
strip_world_graphics(supply)
supply.picture = invisible_sprite()
supply.pictures = invisible_4way()
data:extend({supply})

local hopper = table.deepcopy(data.raw.container["wooden-chest"])
hopper.name = "cncharvester-scoop-hopper"
hopper.icon = "__Red-Alert-Harvesters__/graphics/icons/harv_icon.png"
hopper.icon_size = 32
hopper.minable = nil
hopper.max_health = 1
hopper.collision_box = {{-0.15, -0.15}, {0.15, 0.15}}
hopper.collision_mask = {layers = {}}
hopper.inventory_size = 20
hopper.inventory_type = "normal"
hopper.circuit_wire_max_distance = 0
hopper.next_upgrade = nil
hopper.fast_replaceable_group = nil
hopper.placeable_by = nil
strip_world_graphics(hopper)
hopper.picture = invisible_sprite()
data:extend({hopper})
