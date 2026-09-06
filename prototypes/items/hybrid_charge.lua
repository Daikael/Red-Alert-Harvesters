-- Hidden, non-craftable burner identity for the hybrid energy pool.
-- Never in recipes. Never inserted as a lootable stack (runtime currently_burning
-- only; scrubbed on mine). Dedicated fuel category so Factorio cannot substitute
-- nuclear-fuel / uranium-fuel-cell when remaining hits 0.
--
-- fuel_value 80 MJ = 20 coal: remaining can hold converted solids. Writing
-- currently_burning fills remaining to this value; HybridDrive.lock_charge
-- always clamps afterward. Spark is 2 kJ. Grid/battery refill is rate-capped
-- but can fill up to the 80 MJ pool (the old 4 s / 300 kJ cap hid the bar).
data:extend({
	{
		type = "fuel-category",
		name = "cncharvester-hybrid",
		localised_name = {"fuel-category-name.cncharvester-hybrid"},
		localised_description = {"fuel-category-description.cncharvester-hybrid"}
	},
	{
		type = "item",
		name = "cncharvester-hybrid-charge",
		localised_name = {"item-name.cncharvester-hybrid-charge"},
		localised_description = {"item-description.cncharvester-hybrid-charge"},
		icon = "__Red-Alert-Harvesters__/graphics/equipment/Hybrid-drive.png",
		icon_size = 64,
		hidden = true,
		hidden_in_factoriopedia = true,
		stack_size = 1,
		fuel_value = "80MJ",
		fuel_category = "cncharvester-hybrid",
		flags = {"hide-from-bonus-gui", "hide-from-fuel-tooltip", "not-stackable"}
	}
})
