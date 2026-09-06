-- Leftover hidden item from 2.1.1–2.1.2. Hybrid-drive no longer assigns this
-- as LuaBurner.currently_burning (that filled remaining_burning_fuel to the
-- item's full fuel_value and testers reported a nuclear-cell kickoff).
-- Kept so old saves/blueprints that mention the name still load.
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
