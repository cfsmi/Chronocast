-- Spatial filtering must be invisible: indexed queries agree with a full scan.
return function()
	local Chronocast = require(game.ReplicatedStorage.Chronocast)
	local SpatialIndex = require(game.ReplicatedStorage.Chronocast.SpatialIndex)
	local QueryEngine = require(game.ReplicatedStorage.Chronocast.Query)
	local C = Chronocast.Collision

	-- Unit behaviour of the history grid.
	local index = SpatialIndex.new(10)
	local fake = { Id = "fake" }
	local box = C.Box({ Size = Vector3.new(2, 2, 2) })
	local function snapshot(time, position, collision)
		return { Time = time, Transform = CFrame.new(position), Collision = collision }
	end
	local function finds(min, max)
		local found = index:query(min, max)
		return found ~= nil and found[fake] == true
	end
	index:addSample(fake, snapshot(1, Vector3.new(5, 5, 5), box))
	assert(finds(Vector3.zero, Vector3.new(9, 9, 9)), "sample cell should be found")
	assert(not finds(Vector3.new(100, 100, 100), Vector3.new(101, 101, 101)), "distant cells should be empty")
	index:addSample(fake, snapshot(2, Vector3.new(45, 5, 5), box))
	assert(finds(Vector3.new(25, 5, 5), Vector3.new(25, 5, 5)), "segments between samples must be covered")
	local arm = C.Box({ Offset = CFrame.new(20, 0, 0), Size = Vector3.new(2, 2, 2) })
	local spinner = { Id = "spinner" }
	index:addSample(spinner, snapshot(1, Vector3.new(500, 0, 0), arm))
	local swung = index:query(Vector3.new(479, 0, 0), Vector3.new(481, 0, 0))
	assert(swung and swung[spinner], "offset shapes must be covered under any interpolated rotation")
	index:removeTimeline(spinner)
	index:removeSample(fake, 1)
	assert(finds(Vector3.new(45, 5, 5), Vector3.new(45, 5, 5)), "remaining samples stay indexed after eviction")
	index:addSample(fake, snapshot(3, Vector3.new(5000, 5, 5), box))
	assert(
		finds(Vector3.new(-900, -900, -900), Vector3.new(-899, -899, -899)),
		"oversized samples are always candidates"
	)
	assert(
		index:query(Vector3.new(-1e5, -1e5, -1e5), Vector3.new(1e5, 1e5, 1e5)) == nil,
		"huge regions fall back to a scan"
	)
	index:removeTimeline(fake)
	assert(
		index:cellCount() == 0 and next(index:query(Vector3.zero, Vector3.one)) == nil,
		"removal must release every cell"
	)
	index:addSample(fake, snapshot(1, Vector3.zero, nil))
	assert(index:cellCount() == 0, "samples without collision occupy no cells")
	index:removeTimeline(fake)

	-- Property test: random motion, rotation, teleports and eviction; compare with a full scan.
	local seed = 1234567
	local function random()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local function range(lo, hi)
		return lo + (hi - lo) * random()
	end
	local function direction()
		local v = Vector3.new(range(-1, 1), range(-1, 1), range(-1, 1))
		return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
	end
	local shapes = {
		C.Box({ Offset = CFrame.new(30, 0, 0), Size = Vector3.new(6, 1, 1) }), -- rotation swings a long arm
		C.Sphere({ Offset = CFrame.new(0, 2, 0), Radius = 1.5 }),
		C.Capsule({ Radius = 1, Height = 3 }),
		C.Compound({
			C.Box({ Name = "Body", Size = Vector3.new(2, 3, 1) }),
			C.Sphere({ Name = "Head", Offset = CFrame.new(0, 2.5, 0), Radius = 0.7 }),
		}),
	}
	local ids, all, mine = {}, {}, {}
	local ok, err = xpcall(function()
		local adapters = {}
		for i = 1, 30 do
			local adapter = { CFrame = CFrame.new(range(-60, 60), range(-10, 10), range(-60, 60)) }
			function adapter:GetTransform()
				return self.CFrame
			end
			local timeline = Chronocast:Track({
				Id = string.format("__Spatial_%02d", i),
				Adapter = adapter,
				Collision = shapes[(i - 1) % #shapes + 1],
				SnapshotInterval = 0.05,
				HistoryDuration = 0.5,
			})
			table.insert(ids, timeline.Id)
			table.insert(all, timeline)
			mine[timeline] = true
			adapters[timeline] = adapter
		end
		local base = Chronocast:GetServerTime() + 10
		for step = 1, 40 do
			for _, timeline in ipairs(all) do
				local adapter = adapters[timeline]
				local position = adapter.CFrame.Position + Vector3.new(range(-8, 8), range(-2, 2), range(-8, 8))
				if random() < 0.01 then
					position += Vector3.new(range(-3000, 3000), 0, 0)
				end
				adapter.CFrame = CFrame.new(position) * CFrame.Angles(range(0, 6.3), range(0, 6.3), range(0, 6.3))
				timeline:captureSnapshot(base + step * 0.1)
			end
		end
		local function onlyMine(timeline)
			return mine[timeline] == true
		end
		local function bruteFor(context)
			return {
				_candidates = function()
					return all
				end,
				getState = function(_, timeline)
					return context:GetState(timeline)
				end,
				getCollision = function(_, timeline)
					return context:GetCollision(timeline)
				end,
			}
		end
		local rayHits, overlapHits = 0, 0
		for trial = 1, 300 do
			local time = base + range(-0.5, 4.5)
			local origin = Vector3.new(range(-70, 70), range(-12, 12), range(-70, 70))
			local aim, reach = direction(), range(10, 120)
			if trial % 2 == 0 then
				reach = range(60, 250)
				-- Aim near a target's historical position so rays exercise hits as well as misses.
				local aimContext = Chronocast:CreateContext(time)
				local state = aimContext:GetState(all[(trial // 2) % #all + 1])
				aimContext:Destroy()
				local offset = state.Transform.Position + Vector3.new(range(-2, 2), range(-2, 2), range(-2, 2)) - origin
				if offset.Magnitude > 1e-3 then
					aim = offset.Unit
				end
			end
			local castParams = {
				Shape = "Ray",
				Parameters = { Origin = origin, Direction = aim, MaxDistance = reach },
				Filter = onlyMine,
			}
			local indexed = Chronocast:CreateContext(time)
			local got = indexed:Cast(castParams)
			local scanContext = Chronocast:CreateContext(time)
			local expected = QueryEngine.cast(bruteFor(scanContext), castParams)
			assert((got == nil) == (expected == nil), "indexed Cast hit/miss differs from full scan in trial " .. trial)
			if got then
				rayHits += 1
				assert(
					got.Timeline == expected.Timeline and math.abs(got.Distance - expected.Distance) < 1e-9,
					"indexed Cast result differs from full scan in trial " .. trial
				)
			end
			indexed:Destroy()
			scanContext:Destroy()

			local overlapParams =
				{ Shape = "Sphere", Parameters = { Origin = origin, Radius = range(5, 40) }, Filter = onlyMine }
			indexed = Chronocast:CreateContext(time)
			local gotList = indexed:Overlap(overlapParams)
			scanContext = Chronocast:CreateContext(time)
			local expectedList = QueryEngine.overlap(bruteFor(scanContext), overlapParams)
			assert(#gotList == #expectedList, "indexed Overlap count differs from full scan in trial " .. trial)
			for i, entry in ipairs(gotList) do
				assert(entry.Timeline == expectedList[i].Timeline, "indexed Overlap order differs in trial " .. trial)
			end
			overlapHits += #gotList
			indexed:Destroy()
			scanContext:Destroy()
		end
		print(string.format("SpatialIndex property test: %d ray hits, %d overlap hits", rayHits, overlapHits))
		assert(rayHits >= 20 and overlapHits >= 100, "property test must exercise hits, not only misses")
	end, debug.traceback)
	for _, id in ipairs(ids) do
		Chronocast:Untrack(id)
	end
	if not ok then
		error(err, 0)
	end
end
