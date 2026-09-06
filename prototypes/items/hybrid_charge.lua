-- Hidden chemical identity for the Hybrid-drive spark / joule buffer.
-- Never inserted into the fuel inventory. Writing LuaBurner.currently_burning
-- fills remaining_burning_fuel to this item's fuel_value; runtime always clamps
-- to SPARK_JOULES (2 kJ) or the 4 s hybrid cap so placement is not a full bar.
-- 400 kJ is just above the type-2 cap (350 kJ) so a missed clamp is still far
-- below coal (4 MJ). Scrubbed on mine so it cannot drop as loot.
data:extend({
	{
		type = "item",
		name = "cncharvester-hybrid-charge",
		icon = "__Red-Alert-Harvester__/graphics/equipment/Hybrid-drive.png",
		icon_size = 64,
		hidden = true,
		hidden_in_factoriopedia = true,
		stack_size = 1,
		fuel_value = "400kJ",
		fuel_category = "chemical",
		flags = {"hide-from-bonus-gui", "hide-from-fuel-tooltip"}
	}
})
