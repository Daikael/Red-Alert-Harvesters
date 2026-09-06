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

-- Private pole: supply_area covers the slaved drill; wire distance 0 so it
-- never joins the factory copper grid (that would dump hybrid power out).
local pole = table.deepcopy(data.raw["electric-pole"]["small-electric-pole"])
pole.name = "cncharvester-drill-pole"
pole.icon = "__Red-Alert-Harvesters__/graphics/icons/harv_icon.png"
pole.icon_size = 32
pole.hidden = true
pole.hidden_in_factoriopedia = true
pole.flags = HIDDEN_FLAGS
pole.minable = nil
pole.max_health = 1
pole.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
pole.collision_mask = {layers = {}}
pole.selection_box = {{-0.1, -0.1}, {0.1, 0.1}}
pole.selectable_in_game = false
pole.maximum_wire_distance = 0
pole.supply_area_distance = 1
pole.draw_copper_wires = false
pole.draw_circuit_wires = false
pole.next_upgrade = nil
pole.fast_replaceable_group = nil
pole.placeable_by = nil
data:extend({pole})

local supply = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
supply.name = "cncharvester-drill-supply"
supply.icon = "__Red-Alert-Harvesters__/graphics/icons/harv_icon.png"
supply.icon_size = 32
supply.hidden = true
supply.hidden_in_factoriopedia = true
supply.flags = HIDDEN_FLAGS
supply.minable = nil
supply.max_health = 1
supply.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
supply.collision_mask = {layers = {}}
supply.selection_box = {{-0.1, -0.1}, {0.1, 0.1}}
supply.selectable_in_game = false
supply.gui_mode = "none"
supply.allow_copy_paste = false
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
data:extend({supply})

local hopper = table.deepcopy(data.raw.container["wooden-chest"])
hopper.name = "cncharvester-scoop-hopper"
hopper.icon = "__Red-Alert-Harvesters__/graphics/icons/harv_icon.png"
hopper.icon_size = 32
hopper.hidden = true
hopper.hidden_in_factoriopedia = true
hopper.flags = HIDDEN_FLAGS
hopper.minable = nil
hopper.max_health = 1
hopper.collision_box = {{-0.15, -0.15}, {0.15, 0.15}}
hopper.collision_mask = {layers = {}}
hopper.selection_box = {{-0.15, -0.15}, {0.15, 0.15}}
hopper.selectable_in_game = false
hopper.inventory_size = 20
hopper.inventory_type = "normal"
hopper.circuit_wire_max_distance = 0
hopper.next_upgrade = nil
hopper.fast_replaceable_group = nil
hopper.placeable_by = nil
data:extend({hopper})
