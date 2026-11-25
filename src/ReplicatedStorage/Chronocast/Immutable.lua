-- Utilities for immutable snapshot data and independent configuration copies.
local Immutable = {}

local VALUE_TYPES = {
	Axes = true,
	BrickColor = true,
	CFrame = true,
	CatalogSearchParams = true,
	Color3 = true,
	DateTime = true,
	EnumItem = true,
	Faces = true,
	Font = true,
	NumberRange = true,
	NumberSequence = true,
	PhysicalProperties = true,
	Ray = true,
	Rect = true,
	Region3 = true,
	Region3int16 = true,
	UDim = true,
	UDim2 = true,
	Vector2 = true,
	Vector2int16 = true,
	Vector3 = true,
	Vector3int16 = true,
	TweenInfo = true,
}

local function runtimeType(value)
	if typeof then
		return typeof(value)
	end
	return type(value)
end

local function copyValue(value, seen)
	local kind = type(value)
	if kind ~= "table" then
		local valueType = runtimeType(value)
		assert(kind == "nil" or kind == "number" or kind == "string" or kind == "boolean" or VALUE_TYPES[valueType],
			"Unsupported mutable value in immutable data: " .. tostring(valueType))
		return value
	end

	assert(getmetatable(value) == nil, "Immutable data tables must not have metatables")
	if seen[value] then
		return seen[value]
	end

	local result = {}
	seen[value] = result
	for key, item in pairs(value) do
		local copiedKey = copyValue(key, seen)
		result[copiedKey] = copyValue(item, seen)
	end
	return result
end

local function freezeGraph(value, visited)
	if type(value) ~= "table" or visited[value] then
		return
	end
	visited[value] = true
	for key, item in pairs(value) do
		freezeGraph(key, visited)
		freezeGraph(item, visited)
	end
	if table.freeze then
		table.freeze(value)
	end
end

--- Deep-copies a plain-table graph, preserving cycles and shared references.
--- Snapshot values may also contain supported immutable Roblox value types.
function Immutable.copy(value)
	return copyValue(value, {})
end

--- Copies and recursively freezes a plain-table graph.
function Immutable.copyAndFreeze(value)
	local result = copyValue(value, {})
	freezeGraph(result, {})
	return result
end

--- Copies configuration tables while retaining opaque adapters/Instances as references.
--- Plain nested tables are independently copied; metatable-bearing tables are opaque.
function Immutable.copyConfig(value, seen)
	if type(value) ~= "table" then
		return value
	end
	if getmetatable(value) ~= nil then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local result = {}
	seen[value] = result
	for key, item in pairs(value) do
		result[Immutable.copyConfig(key, seen)] = Immutable.copyConfig(item, seen)
	end
	return result
end

return Immutable
