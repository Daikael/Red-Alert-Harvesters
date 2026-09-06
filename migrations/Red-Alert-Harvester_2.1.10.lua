-- Re-apply unlocks after Tiberium moved off Old-World-Harvesting and
-- Hybrid-drive recipes were removed.
for _, force in pairs(game.forces) do
	force.reset_technology_effects()
end
