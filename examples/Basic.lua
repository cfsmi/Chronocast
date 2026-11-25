-- Minimal end-to-end example. Invoke during Play from a server Script or the server
-- Command Bar, with Chronocast in ReplicatedStorage:
-- require(path.to.Basic)()
-- It creates one temporary anchored part and cleans up after itself.
return function()
	local Chronocast = require(game:GetService("ReplicatedStorage").Chronocast)
	local part = Instance.new("Part")
	part.Name = "ChronocastDemo"
	part.Anchored = true
	part.Size = Vector3.new(4, 4, 4)
	part.CFrame = CFrame.new(0, 10, 0)
	part.Parent = workspace

	local timeline
	local ok, result = xpcall(function()
		timeline = Chronocast:Track({
			Id = "ChronocastDemo",
			Instance = part, -- alternatively supply an Adapter with GetTransform
			Collision = Chronocast.Collision.FromPart(part), -- local to part.CFrame
			SnapshotInterval = 1 / 30,
		})
		local pastTime = Chronocast:GetServerTime()
		task.wait(0.1)
		part.Position = Vector3.new(20, 10, 0)
		task.wait(0.1) -- snapshots are captured automatically

		local context = Chronocast:CreateContext(pastTime)
		local state = context:GetState(timeline)
		local hit = context:Cast({
			Shape = "Ray",
			Parameters = {
				Origin = Vector3.new(-10, 10, 0),
				Direction = Vector3.xAxis,
				MaxDistance = 30,
			},
		})
		print("Historical position:", state.Transform.Position, "Historical hit:", hit ~= nil, hit and hit.Distance)
		context:Destroy()
		return hit
	end, debug.traceback)
	if timeline then
		timeline:Destroy()
	end
	part:Destroy()
	if not ok then
		error(result, 0)
	end
	return result
end
