-- Chronocast v2 - Configuration
-- Global defaults and per-timeline overrides are copied at every boundary.

local Immutable = require(script.Parent.Immutable)
local Config = {}

local DEFAULTS = {
	SnapshotRate = 0.033,
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
	for _, key in ipairs({ "SnapshotRate", "HistoryDuration" }) do
		local value = config[key]
		assert(type(value) == "number" and value == value and value > 0 and value < math.huge,
			key .. " must be a finite positive number")
	end
	assert(config.Interpolation.Extrapolate ~= true,
		"Interpolation.Extrapolate=true is unsupported; use snapshots within recorded history")
	return config
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
	return validate(mergeInto(Immutable.copyConfig(DEFAULTS), overrides))
end

--- Merges defaults, global configuration, and timeline overrides independently.
function Config.merge(globalConfig, overrides)
	local merged = Immutable.copyConfig(DEFAULTS)
	mergeInto(merged, globalConfig)
	mergeInto(merged, overrides)
	return validate(merged)
end

function Config.calculateBufferCapacity(rate, duration)
	if rate <= 0 then
		return DEFAULTS.BufferCapacity
	end
	return math.ceil(duration / rate) + 5
end

return Config
