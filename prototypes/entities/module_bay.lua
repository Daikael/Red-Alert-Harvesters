-- Companion mining-drill shells. Cars cannot host module_slots; these entities can.
-- Dummy resource category so the drill never actually mines (scripted scoop only).

data:extend({
	{
		type = "resource-category",
		name = "cncharvester-module-bay"
	}
})

local function bay_animation()
	local frame = {
		filename = "__Red-Alert-Harvester__/graphics/icons/harv_icon.png",
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

local function module_bay(name, slots, icon)
	return {
		type = "mining-drill",
		name = name,
		icon = icon,
		icon_size = 32,
		hidden = true,
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
		-- Dummy category: no resource uses this, so the drill never extracts.
		resource_categories = {"cncharvester-module-bay"},
		resource_searching_radius = 0.01,
		vector_to_place_result = {0, 0},
		mining_speed = 0.0001,
		energy_usage = "1W",
		energy_source = {type = "void"},
		module_slots = slots,
		-- Testers: quality-scaled extra slots were OP. Always 2 / 3.
		quality_affects_module_slots = false,
		allowed_effects = {"speed", "productivity", "consumption", "pollution", "quality"},
		graphics_set = {
			animation = bay_animation()
		}
	}
end

data:extend({
	module_bay("cncharvester-module-bay", 2, "__Red-Alert-Harvester__/graphics/icons/harv_icon.png"),
	module_bay("cncharvester-type2-module-bay", 3, "__Red-Alert-Harvester__/graphics/icons/harv_icon-type2.png"),
})
