-- Recreate slave-miner helpers (pole / supply / hopper) after the dummy
-- void-energy bay became a real electric drill.
if ModuleBay and ModuleBay.attach_existing then
	ModuleBay.attach_existing()
end
