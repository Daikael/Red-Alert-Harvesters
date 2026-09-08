require "specialOres"

function Error(text)
	log("Red-Alert-Harvesters: " .. tostring(text or "unknown error"))
	if game and game.print then
		game.print({"", "[C&C Harvesters] ", text or "unknown error"})
	end
end

function DeltaposToOrientation(dPos)
	if dPos.x == 0 then
		if dPos.y > 0 then
			return 0.5
		else
			return 0
		end
	elseif dPos.x > 0 then
		return (math.atan(dPos.y / dPos.x) / (2 * math.pi) + 0.25)
	else
		return (math.atan(dPos.y / dPos.x) / (2 * math.pi) + 0.75)
	end
end

function GetBoundingBox(position, radius)
	return {
		{position.x - radius, position.y - radius},
		{position.x + radius, position.y + radius}
	}
end

function FindNearestEntity(baseEntity, entList)
	local closestEntity = false
	local minDist = math.huge
	for _, entity in pairs(entList) do
		local dPos = Vector.subtract(baseEntity.position, entity.position)
		local dist = Vector.length(dPos)

		if dist < minDist then
			closestEntity = entity
			minDist = dist
		end
	end
	return closestEntity
end

function ItemPrototype(name)
	return prototypes.item[name]
end

function EntityPrototype(name)
	return prototypes.entity[name]
end

-- 2.0/2.1 get_contents() returns { {name=, count=, quality=}, ... } instead of a name->count map.
-- Scooping rolls quality in scoop.lua; this helper preserves stack quality on unload.
function EachInventoryItem(inventory, callback)
	if not (inventory and inventory.valid) then
		return
	end
	for _, item in pairs(inventory.get_contents()) do
		callback(item.name, item.count, item.quality)
	end
end

function InventoryItemStack(name, count, quality)
	local stack = {name = name, count = count}
	if quality then
		stack.quality = quality
	end
	return stack
end

-- Entity / stack quality is a Space Age (quality mod) field. Base 2.0
-- without that mod may error on .quality; treat as nil (level 0).
function SafeQuality(obj)
	if not obj then
		return nil
	end
	local ok, quality = pcall(function()
		return obj.quality
	end)
	if ok then
		return quality
	end
	return nil
end

function GetOccupiedSlots(inventory)
	local slotsOccupied = 0
	EachInventoryItem(inventory, function(itemName, count)
		local proto = ItemPrototype(itemName)
		local stack_size = proto and proto.stack_size or 50
		slotsOccupied = slotsOccupied + math.ceil(count / stack_size)
	end)
	return slotsOccupied
end

local SLAVE_BAY_FOR = {
	["cncharvester"] = "cncharvester-module-bay",
	["cncharvester-type2"] = "cncharvester-type2-module-bay",
}

-- Match the slave miner's real resource_categories. Never require a
-- basic-solid-tiberium prototype that only exists with Factorio-Tiberium.
function IsHarvestableResource(entity, vehicle)
	if not (entity and entity.valid) then
		return false
	end
	local category = entity.prototype.resource_category
	if category == "basic-fluid" or category == "lava-magma" then
		return false
	end
	if vehicle and vehicle.valid and vehicle.name and prototypes and prototypes.entity then
		local bay_name = SLAVE_BAY_FOR[vehicle.name]
		local bay_proto = bay_name and prototypes.entity[bay_name]
		if bay_proto and bay_proto.resource_categories then
			if not bay_proto.resource_categories[category] then
				return false
			end
		elseif category ~= "basic-solid" then
			return false
		end
	elseif category ~= "basic-solid" then
		if not (category and string.find(category, "tiberium", 1, true)) then
			return false
		end
	end
	local props = entity.prototype.mineable_properties
	return props and props.minable and props.products
end

function ResourceProductItemName(entity)
	if SpecialOres and SpecialOres[entity.name] then
		return SpecialOres[entity.name]()
	end
	local props = entity.prototype.mineable_properties
	if props and props.products then
		for _, product in pairs(props.products) do
			if (not product.type or product.type == "item") and product.name then
				return product.name
			end
		end
	end
	return entity.name
end

-- Error-red harvest warnings (trunk full / blocked scoop). 150 ticks ≈ 2.5s at 60 UPS.
-- Informational text (refuel, etc.) must pass its own color and must not use these.
FLOATING_TEXT_ERROR_RED = {r = 1, g = 0.2, b = 0.2, a = 1}
FLOATING_TEXT_ERROR_TTL = 150
-- Toggle / inventory feedback. 300 ticks ≈ 5s at 60 UPS (Steam Deck readable).
FLOATING_TEXT_TOGGLE_TTL = 300

function DrawFloatingText(surface, target, text, color, ttl)
	if not (surface and surface.valid) then
		return
	end
	rendering.draw_text{
		text = text,
		surface = surface,
		target = target,
		color = color or {r = 1, g = 1, b = 1, a = 1},
		scale = 1.4,
		scale_with_zoom = true,
		time_to_live = ttl or 20
	}
end

Vector = {
	add = function(p1, p2)
		if not p2.x then
			return {x = p1.x + p2[1], y = p1.y + p2[2]}
		end
		return {x = p1.x + p2.x, y = p1.y + p2.y}
	end,

	subtract = function(p1, p2)
		if not p2.x then
			return {x = p1.x - p2[1], y = p1.y - p2[2]}
		end
		return {x = p1.x - p2.x, y = p1.y - p2.y}
	end,

	mul = function(p1, c)
		return {x = p1.x * c, y = p1.y * c}
	end,

	div = function(p1, c)
		return {x = p1.x / c, y = p1.y / c}
	end,

	dist = function(p1, p2)
		return Vector.length(Vector.subtract(p1, p2))
	end,

	distsq = function(p1, p2)
		return Vector.lengthsq(Vector.subtract(p1, p2))
	end,

	length = function(vec)
		return math.sqrt((vec.x * vec.x) + (vec.y * vec.y))
	end,

	lengthsq = function(vec)
		return (vec.x * vec.x) + (vec.y * vec.y)
	end,

	normalized = function(vec)
		local length = Vector.length(vec)
		return {x = vec.x / length, y = vec.y / length}
	end,
}
