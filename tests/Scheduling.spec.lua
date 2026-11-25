-- Run in a live server. Exercises only the documented public API.
return function()
	local Chronocast = require(game.ReplicatedStorage.Chronocast)
	local RunService = game:GetService("RunService")
	assert(RunService:IsRunning(), "Scheduling tests require Play mode")
	local part = Instance.new("Part")
	part.Anchored = true
	part.CFrame = CFrame.new(10000, 10000, 10000)
	part.Parent = workspace
	local ids = { "__ChronocastSchedule", "__ChronocastAdapter" }
	local timeline, virtual
	local ok, err = xpcall(function()
		local now = Chronocast:GetServerTime()
		assert(math.abs(now - workspace:GetServerTimeNow()) < 0.25, "Clock must share Roblox server epoch")
		timeline = Chronocast:Track({
			Id = ids[1],
			Instance = part,
			SnapshotRate = 0.03,
			Collision = Chronocast.Collision.FromPart(part),
		})
		assert(#timeline:GetSnapshots() == 1, "Track must capture the first sample")
		local first = timeline:GetSnapshots()[1]
		part.CFrame = part.CFrame + Vector3.new(12, 0, 0)
		task.wait(0.2)
		local snapshots = timeline:GetSnapshots()
		assert(#snapshots >= 2, "Heartbeat must capture without caller intervention")
		for i = 2, #snapshots do
			assert(snapshots[i].Time - snapshots[i - 1].Time >= 0.029, "Capture interval was ignored")
		end
		local context = Chronocast:CreateContext(first.Time)
		assert(
			(context:GetState(timeline).Transform.Position - first.Transform.Position).Magnitude < 1e-5,
			"Historical position must survive movement"
		)
		local result = context:Query({
			Shape = "Ray",
			Parameters = {
				Origin = first.Transform.Position - Vector3.new(10, 0, 0),
				Direction = Vector3.xAxis,
				MaxDistance = 20,
			},
		})
		assert(
			result.Hit and result.Timeline == timeline,
			"Generated collision must be root-local, not double translated"
		)
		context:Destroy()
		timeline:SetCollision(Chronocast.Collision.Sphere({ Radius = 8 }))
		task.wait(0.1)
		assert(first.Collision.Shape == "Box", "Collision replacement must not rewrite old snapshots")
		assert(
			timeline:GetSnapshots()[#timeline:GetSnapshots()].Collision.Shape == "Sphere",
			"New captures must use new collision"
		)
		local historical = Chronocast:CreateContext(first.Time)
		assert(historical:GetCollision(timeline).Shape == "Box", "Historical context must use recorded collision")
		historical:Destroy()
		assert(not pcall(function()
			Chronocast:Track({ Id = ids[1], Instance = part })
		end), "Duplicate Id must fail")
		assert(not pcall(function()
			Chronocast:Track({ Id = "__InvalidAdapter" })
		end), "Missing source must fail")
		assert(not pcall(function()
			Chronocast:Track({ Id = "__InvalidRate", Instance = part, SnapshotRate = 0 })
		end), "Invalid rate must fail")
		virtual = Chronocast:Track({
			Id = ids[2],
			Adapter = {
				GetTransform = function()
					return CFrame.new()
				end,
				Metadata = {
					Flag = function()
						return false
					end,
					Omitted = function()
						return nil
					end,
				},
			},
		})
		assert(virtual:GetSnapshots()[1].Metadata.Flag == false, "False metadata provider values must survive")
		assert(virtual:GetSnapshots()[1].Metadata.Omitted == nil, "Nil metadata provider values must survive")
		Chronocast:Untrack(ids[1])
		assert(timeline:isDestroyed(), "Untrack must destroy and release history")
		assert(#timeline:GetSnapshots() == 0, "Untrack must clear history")
		timeline:Destroy() -- idempotent
		virtual:Destroy() -- direct destruction unregisters too
		local replacement = Chronocast:Track({ Id = ids[2], Instance = part })
		replacement:Destroy()
	end, debug.traceback)
	for _, id in ipairs(ids) do
		Chronocast:Untrack(id)
	end
	part:Destroy()
	if not ok then
		error(err, 0)
	end
	return "automatic capture, clock, history query, validation, metadata and lifecycle passed"
end
