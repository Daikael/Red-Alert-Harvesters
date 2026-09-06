-- Hidden chemical fuel used only as LuaBurner.currently_burning when Hybrid-drive
-- starts a charge with an empty fuel tank. Never inserted into the fuel inventory.
data:extend({
	{
		type = "item",
		name = "cncharvester-hybrid-charge",
		icon = "__Red-Alert-Harvester__/graphics/equipment/Hybrid-drive.png",
		icon_size = 64,
		hidden = true,
		hidden_in_factoriopedia = true,
		stack_size = 1,
		fuel_value = "1MJ",
		fuel_category = "chemical",
		flags = {"hide-from-bonus-gui", "hide-from-fuel-tooltip"}
	}
})
