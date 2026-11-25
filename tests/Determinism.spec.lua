-- Context membership pinning, cached historical views, and binary-search history lookups.
-- Captures use explicit future times and never yield, so Heartbeat cannot interleave.
return function()
	local Chronocast = require(game.ReplicatedStorage.Chronocast)
	local RingBuffer = require(game.ReplicatedStorage.Chronocast.History.RingBuffer)
	local ids, mine = {}, {}
	local function track(name, x)
		local adapter = { Position = Vector3.new(x, 0, 0) }
		function adapter:GetTransform()
			return CFrame.new(self.Position)
		end
		local timeline = Chronocast:Track({
			Id = "__Determinism_" .. name,
			SnapshotInterval = 0.05,
			HistoryDuration = 0.5,
			Collision = Chronocast.Collision.Box({ Size = Vector3.new(2, 2, 2) }),
			Adapter = adapter,
		})
		table.insert(ids, timeline.Id)
		mine[timeline] = true
		return timeline, adapter
	end
	local function onlyMine(timeline)
		return mine[timeline] == true
	end

	local ok, err = xpcall(function()
		local base = Chronocast:GetServerTime() + 10
		local times = {}
		for i = 1, 60 do
			times[i] = base + i * 0.1
		end
		local a, adapterA = track("A", 0)
		for i = 1, 5 do
			a:captureSnapshot(times[i])
		end
		local t = times[3]
		local context = Chronocast:CreateContext(t)

		-- Membership is pinned at creation: B is tracked afterwards and stays invisible.
		local b = track("B", 20)
		for i = 6, 7 do
			a:captureSnapshot(times[i])
			b:captureSnapshot(times[i])
		end
		local volume =
			{ Shape = "Sphere", Parameters = { Origin = Vector3.new(10, 0, 0), Radius = 15 }, Filter = onlyMine }
		local pinned = context:Overlap(volume)
		assert(#pinned == 1 and pinned[1].Timeline == a, "a context must not see timelines tracked after it")
		local fresh = Chronocast:CreateContext(t)
		local both = fresh:Overlap(volume)
		assert(
			#both == 2 and both[1].Timeline == a and both[2].Timeline == b,
			"a new context sees current membership, Id-sorted"
		)
		fresh:Destroy()

		-- GetSnapshots is the history recorded up to the context time, frozen on first access.
		local snapshots = context:GetSnapshots(a)
		assert(table.isfrozen(snapshots) and #snapshots >= 3, "context snapshots must be frozen")
		assert(snapshots[#snapshots].Time == t, "context snapshots must end at the context time")
		for _, snapshot in ipairs(snapshots) do
			assert(snapshot.Time <= t, "no snapshot may follow the context time")
		end
		a:captureSnapshot(times[8])
		assert(context:GetSnapshots(a) == snapshots, "context snapshots must be cached")

		-- A state read once survives eviction: A moves away and all nearby history rolls out.
		local ray = {
			Shape = "Ray",
			Parameters = { Origin = Vector3.new(-10, 0, 0), Direction = Vector3.xAxis, MaxDistance = 100 },
			Filter = function(timeline)
				return timeline == a
			end,
		}
		local before = context:Cast(ray)
		assert(before and before.Timeline == a and before.Distance == 9, "historical ray should hit A at x = -1")
		adapterA.Position = Vector3.new(500, 0, 0)
		for i = 9, 40 do
			a:captureSnapshot(times[i])
		end
		local after = context:Cast(ray)
		assert(
			after and after.Timeline == a and after.Distance == before.Distance,
			"cached state must keep answering identically"
		)
		local late = Chronocast:CreateContext(t)
		assert(late:Cast(ray) == nil, "a new context clamps to the oldest retained snapshot")
		late:Destroy()

		context:Destroy()
		assert(not pcall(function()
			context:Cast(ray)
		end), "Cast on a destroyed context must error")
		assert(
			context:Query({ Shape = "Ray", Parameters = ray.Parameters }).Hit == false,
			"legacy Query keeps its miss shape"
		)

		-- Binary-search bracketing matches a brute-force scan across a wrapped buffer.
		local ring = RingBuffer.new(7)
		for i = 1, 12 do
			ring:push({ Time = i * 0.5 })
		end
		for q = 0, 70 do
			local time = q * 0.1
			local expectBefore, expectAfter
			for entry in ring:entries() do
				if entry.Time <= time then
					expectBefore = entry
				end
				if entry.Time >= time and expectAfter == nil then
					expectAfter = entry
				end
			end
			local gotBefore, gotAfter = ring:findBracketingSnapshots(time)
			assert(gotBefore == expectBefore and gotAfter == expectAfter, "bracketing mismatch at " .. time)
		end
		assert(ring:nearestSnapshot(4.75).Time == 4.5, "nearest ties prefer the older snapshot")
		assert(
			ring:nearestSnapshot(4.8).Time == 5 and ring:nearestSnapshot(0).Time == 3,
			"nearest must clamp and round"
		)
		local stored, evicted = ring:push({ Time = 6.5 })
		assert(stored.Time == 6.5 and evicted.Time == 3, "push reports the evicted snapshot")
	end, debug.traceback)
	for _, id in ipairs(ids) do
		Chronocast:Untrack(id)
	end
	if not ok then
		error(err, 0)
	end
end
