-- The lag-compensation example's validator: rewinding, clamping and untrusted input.
-- Captures use explicit future times and never yield, so Heartbeat cannot interleave.
return function()
	local Chronocast = require(game.ReplicatedStorage.Chronocast)
	local ShotValidator = require(game.ServerStorage.ChronocastExamples.LagCompensation.ShotValidator)
	local C = Chronocast.Collision

	local ids = {}
	local function track(name, adapter, collision)
		local timeline = Chronocast:Track({
			Id = "__LagComp_" .. name,
			Adapter = adapter,
			Collision = collision,
			SnapshotInterval = 0.02,
			HistoryDuration = 2,
		})
		table.insert(ids, timeline.Id)
		return timeline
	end

	local ok, err = xpcall(function()
		local shooterAdapter = { CFrame = CFrame.new(0, 3, 0) }
		function shooterAdapter:GetTransform()
			return self.CFrame
		end
		local targetAdapter = { CFrame = CFrame.new(0, 3, -20) }
		function targetAdapter:GetTransform()
			return self.CFrame
		end
		local body = C.Compound({
			C.Box({ Name = "Torso", Size = Vector3.new(2, 2, 1) }),
			C.Sphere({ Name = "Head", Offset = CFrame.new(0, 1.6, 0), Radius = 0.6 }),
		})
		local shooter = track("Shooter", shooterAdapter, body)
		local target = track("Target", targetAdapter, body)

		-- The target strafes from x = 0 to x = 10 over 0.5 s of recorded history.
		local base = Chronocast:GetServerTime() + 10
		for i = 1, 25 do
			targetAdapter.CFrame = CFrame.new(i * 0.4, 3, -20)
			shooter:captureSnapshot(base + i * 0.02)
			target:captureSnapshot(base + i * 0.02)
		end
		local now = base + 0.5
		local validator = ShotValidator.new(Chronocast, { InterpolationDelay = 0.1, MaxRewind = 0.3 })

		-- The client saw the target 0.1 s in the past (x = 8) and fired at its head there.
		local origin = Vector3.new(0, 4.6, 0)
		local seenHead = Vector3.new(8, 4.6, -20)
		local hit, viewTime = validator:Validate(shooter, {
			Origin = origin,
			Direction = seenHead - origin,
			ClientTime = now,
		}, now)
		assert(hit and hit.Timeline == target and hit.Name == "Head", "rewound headshot should land")
		assert(math.abs(viewTime - (now - 0.1)) < 1e-9, "view time is client time minus interpolation delay")

		-- The same aim without rewinding (the target is at x = 10 now) misses.
		local unrewound = ShotValidator.new(Chronocast, { InterpolationDelay = 0 })
		local _, reason =
			unrewound:Validate(shooter, { Origin = origin, Direction = seenHead - origin, ClientTime = now }, now)
		assert(reason == "Miss", "without rewinding the target has moved on")

		-- Claims of a very old shot are clamped to MaxRewind, not honoured.
		local clampedHit, clampedView = validator:Validate(shooter, {
			Origin = origin,
			Direction = Vector3.new(4, 4.6, -20) - origin,
			ClientTime = now - 5,
		}, now)
		assert(
			clampedHit and math.abs(clampedView - (now - 0.3)) < 1e-9,
			"old shots resolve at now - MaxRewind (x = 4)"
		)

		-- Untrusted input is rejected with a reason rather than raising.
		local function reasonFor(shot)
			local result, why = validator:Validate(shooter, shot, now)
			assert(result == nil, "malformed shot must not hit")
			return why
		end
		assert(
			reasonFor({ Origin = origin, Direction = Vector3.zero, ClientTime = now }) == "MalformedShot",
			"zero direction"
		)
		assert(
			reasonFor({ Origin = "x", Direction = Vector3.xAxis, ClientTime = now }) == "MalformedShot",
			"wrong type"
		)
		assert(
			reasonFor({ Origin = Vector3.new(0 / 0, 0, 0), Direction = Vector3.xAxis, ClientTime = now })
				== "MalformedShot",
			"NaN origin"
		)
		assert(
			reasonFor({ Origin = origin, Direction = Vector3.xAxis, ClientTime = 0 / 0 }) == "MalformedShot",
			"NaN time"
		)
		assert(reasonFor(nil) == "MalformedShot", "missing shot")
		assert(
			reasonFor({ Origin = origin, Direction = Vector3.xAxis, ClientTime = now + 1 }) == "ClientTimeInFuture",
			"future time"
		)
		assert(
			reasonFor({ Origin = Vector3.new(0, 4.6, -15), Direction = -Vector3.zAxis, ClientTime = now })
				== "OriginMismatch",
			"origin far from the shooter's recorded position"
		)

		-- The shooter can never hit itself, even when firing through its own body.
		local selfShot, selfReason = validator:Validate(shooter, {
			Origin = Vector3.new(0, 3, 3),
			Direction = -Vector3.zAxis,
			ClientTime = now,
		}, now)
		assert(selfShot == nil or selfShot.Timeline ~= shooter, "the shooter is excluded")
		assert(selfShot or selfReason == "Miss", "a shot through yourself is a miss when nothing is behind you")
		assert(not pcall(ShotValidator.new, Chronocast, { Typo = 1 }), "unknown options are rejected")
	end, debug.traceback)
	for _, id in ipairs(ids) do
		Chronocast:Untrack(id)
	end
	if not ok then
		error(err, 0)
	end
end
