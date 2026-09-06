-- Slave mining-drill. Cars cannot host module_slots; this entity can.
-- 2.1.12: the drill actually mines so Factorio applies productivity / efficiency /
-- speed natively. A hidden pole + electric-energy-interface form a private
-- micro-grid (powered from the hybrid pool in control). A hopper catches output.

require("util")

-- World-invisible 1×1. Never reuse one table across 4-way directions
-- (AtlasBuilder can walk x += width and leave the sheet).
local function empty_world_sprite()
	local sprite = util.empty_sprite()
	sprite.filename = "__core__/graphics/empty.png"
	sprite.x = 0
	sprite.y = 0
	sprite.width = 1
	sprite.height = 1
	sprite.frame_count = 1
	sprite.line_length = 1
	sprite.direction_count = 1
	sprite.hr_version = nil
	sprite.shift = {0, 0}
	return sprite
end

-- 2.1.16 leftover: slave-drill graphics_set.animation was harv_icon.png
-- (32×32 ore-truck still) at shift {0.85, 0.85} on BOTH bays. That is the
-- floating bottom-right square testers saw idle and mining. Unused sheets
-- graphics/entity/harv-anim/1.png and harvester/harvester-up-*.png are not
-- referenced by any prototype.
local function empty_4way_animation()
	local function frame()
		return {layers = {empty_world_sprite()}}
	end
	return {
		north = frame(),
		east = frame(),
		south = frame(),
		west = frame()
	}
end

-- Quality prototype keys and the "quality" module effect exist when the
-- quality / space-age mods are loaded. Base 2.0 without Space Age errors
-- on unknown properties if we always set them.
local HAS_QUALITY = mods["quality"] or mods["space-age"] or false

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
	local allowed_effects = {"speed", "productivity", "consumption", "pollution"}
	if HAS_QUALITY then
		table.insert(allowed_effects, "quality")
	end
	local bay = {
		type = "mining-drill",
		name = name,
		icon = icon,
		icon_size = 32,
		-- Selectable for SHIFT+E / click (modules + energy bar) but no world sprite.
		hidden = false,
		hidden_in_factoriopedia = true,
		flags = {
			"placeable-off-grid",
			"not-on-map",
			"not-blueprintable",
			"not-deconstructable",
			"not-repairable",
			"not-flammable",
			"hide-alt-info",
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
		allowed_effects = allowed_effects,
		radius_visualisation_picture = empty_world_sprite(),
		graphics_set = {
			animation = empty_4way_animation()
		}
	}
	-- Omit these on base 2.0 (unknown keys). With Space Age they stay false
	-- so slot count / radius do not scale with entity quality.
	if HAS_QUALITY then
		bay.quality_affects_module_slots = false
		bay.quality_affects_mining_radius = false
	end
	return bay
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

local function strip_world_graphics(ent)
	ent.pictures = nil
	ent.picture = empty_world_sprite()
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
	ent.radius_visualisation_picture = empty_world_sprite()
	ent.integration_patch = nil
	ent.circuit_connector = nil
	ent.circuit_connector_sprites = nil
	ent.corpse = nil
	ent.dying_explosion = nil
	ent.damaged_trigger_effect = nil
	ent.stateless_visualisation = nil
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
-- RotatedSprite direction_count must match connection_points and the sheet.
-- One 1×1 empty frame — never a 4-wide strip on a 1-frame image.
pole.pictures = {
	layers = {
		empty_world_sprite()
	}
}
pole.connection_points = {
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
-- picture wins over pictures/animation; keep all empty and unshared.
supply.picture = empty_world_sprite()
supply.pictures = nil
supply.animation = nil
supply.animations = nil
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
hopper.picture = empty_world_sprite()
hopper.pictures = nil
data:extend({hopper})
