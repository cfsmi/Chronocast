-- Chronocast v2 - Configuration
-- Global defaults and per-timeline overrides are copied at every boundary.

local Immutable = require(script.Parent.Immutable)
local Config = {}

local DEFAULTS = {
	SnapshotInterval = 0.033, -- seconds between captures (not Hz)
	HistoryDuration = 5.0,
	BufferCapacity = 150,
	AutoInferAdapters = true,
	Collision = {
		DefaultShape = "Box",
		Filter = nil,
	},
	Interpolation = {
		PositionMode = "Linear",
		RotationMode = "SLERP",
		VelocityMode = "Sampled",
		FallbackMode = "Nearest",
		Extrapolate = false,
	},
	SpatialIndex = {
		Type = "Grid",
		CellSize = 64,
	},
}

local function validate(config)
	for _, key in ipairs({ "SnapshotInterval", "HistoryDuration" }) do
		local value = config[key]
		assert(
			type(value) == "number" and value == value and value > 0 and value < math.huge,
			key .. " must be a finite positive number"
		)
	end
	assert(
		config.Interpolation.Extrapolate ~= true,
		"Interpolation.Extrapolate=true is unsupported; use snapshots within recorded history"
	)
	return config
end

-- SnapshotRate is the pre-0.2 name of SnapshotInterval and is accepted as an alias.
local function resolveAliases(overrides)
	if type(overrides) ~= "table" or overrides.SnapshotRate == nil then
		return overrides
	end
	assert(
		overrides.SnapshotInterval == nil or overrides.SnapshotInterval == overrides.SnapshotRate,
		"SnapshotRate is an alias of SnapshotInterval; set only one"
	)
	local resolved = table.clone(overrides)
	resolved.SnapshotInterval = overrides.SnapshotRate
	resolved.SnapshotRate = nil
	return resolved
end

local function mergeInto(target, overrides)
	if overrides == nil then
		return target
	end
	for key, value in pairs(overrides) do
		if type(value) == "table" and type(target[key]) == "table" then
			mergeInto(target[key], value)
		else
			target[key] = Immutable.copyConfig(value)
		end
	end
	return target
end

--- Creates an independent global configuration including copied defaults.
function Config.create(overrides)
	return validate(mergeInto(Immutable.copyConfig(DEFAULTS), resolveAliases(overrides)))
end

--- Merges defaults, global configuration, and timeline overrides independently.
function Config.merge(globalConfig, overrides)
	local merged = Immutable.copyConfig(DEFAULTS)
	mergeInto(merged, resolveAliases(globalConfig))
	mergeInto(merged, resolveAliases(overrides))
	return validate(merged)
end

function Config.calculateBufferCapacity(interval, duration)
	if interval <= 0 then
		return DEFAULTS.BufferCapacity
	end
	return math.ceil(duration / interval) + 5
end

return Config
