-- Validates a client-reported hitscan shot against the world as that client saw it.
--
-- The client sends where it fired from, where it aimed, and its estimate of server
-- time when it fired. Other players appear on that client slightly in the past
-- (replication plus interpolation), so the server rewinds by InterpolationDelay,
-- clamps the rewind to MaxRewind, and casts against the reconstructed history.
-- Every field arrives over the network, so every field is treated as untrusted.
local ShotValidator = {}
ShotValidator.__index = ShotValidator

ShotValidator.Defaults = table.freeze({
	-- How far behind the server clock other players appear on clients. Tune by measuring.
	InterpolationDelay = 0.1,
	-- Never rewind further than this, however old the client claims its shot is.
	MaxRewind = 0.3,
	-- Client clocks may run slightly ahead of the server; anything further ahead is rejected.
	MaxClockLead = 0.05,
	-- How far the reported origin may be from the shooter's root at the rewound time.
	MaxOriginError = 6,
	Range = 500,
})

local function isFinite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isFiniteVector(value)
	return typeof(value) == "Vector3" and isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z)
end

--- @param chronocast table - the required Chronocast module
--- @param options table? - overrides for ShotValidator.Defaults
function ShotValidator.new(chronocast, options)
	local config = table.clone(ShotValidator.Defaults)
	for key, value in pairs(options or {}) do
		assert(ShotValidator.Defaults[key] ~= nil, "Unknown ShotValidator option: " .. tostring(key))
		assert(
			isFinite(value) and value >= 0,
			"ShotValidator option " .. key .. " must be a finite non-negative number"
		)
		config[key] = value
	end
	return setmetatable({ Chronocast = chronocast, Config = table.freeze(config) }, ShotValidator)
end

--- Returns the frozen Cast result and the rewound time, or nil and a rejection reason.
--- @param shooter Timeline - the shooting player's timeline; it is never a valid target
--- @param shot { Origin: Vector3, Direction: Vector3, ClientTime: number }
--- @param now number? - server time; defaults to Chronocast:GetServerTime()
function ShotValidator:Validate(shooter, shot, now)
	local config = self.Config
	if type(shot) ~= "table" or not isFiniteVector(shot.Origin) or not isFiniteVector(shot.Direction) then
		return nil, "MalformedShot"
	end
	if shot.Direction.Magnitude < 1e-3 or not isFinite(shot.ClientTime) then
		return nil, "MalformedShot"
	end
	now = now or self.Chronocast:GetServerTime()
	if shot.ClientTime > now + config.MaxClockLead then
		return nil, "ClientTimeInFuture"
	end
	local viewTime = math.clamp(shot.ClientTime - config.InterpolationDelay, now - config.MaxRewind, now)

	local context = self.Chronocast:CreateContext(viewTime)
	local shooterState = context:GetState(shooter)
	if not shooterState then
		context:Destroy()
		return nil, "UnknownShooter"
	end
	if (shooterState.Transform.Position - shot.Origin).Magnitude > config.MaxOriginError then
		context:Destroy()
		return nil, "OriginMismatch"
	end
	local hit = context:Cast({
		Shape = "Ray",
		Parameters = { Origin = shot.Origin, Direction = shot.Direction, MaxDistance = config.Range },
		Filter = function(timeline)
			return timeline ~= shooter
		end,
	})
	context:Destroy()
	if not hit then
		return nil, "Miss"
	end
	return hit, viewTime
end

return ShotValidator
