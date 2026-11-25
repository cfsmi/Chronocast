-- Per-limb character collision and the debug visualizer.
return function()
	local Chronocast = require(game.ReplicatedStorage.Chronocast)
	local C = Chronocast.Collision
	local character = Instance.new("Model")
	local function part(name, cframe, size, parent)
		local instance = Instance.new("Part")
		instance.Name = name
		instance.Size = size
		instance.CFrame = cframe
		instance.Parent = parent or character
		return instance
	end
	local root = part("HumanoidRootPart", CFrame.new(0, 3, 0), Vector3.new(2, 2, 1))
	part("UpperTorso", CFrame.new(0, 3, 0), Vector3.new(2, 2, 1))
	local head = part("Head", CFrame.new(0, 4.5, 0), Vector3.new(1.2, 1.2, 1.2))
	local accessory = Instance.new("Accessory")
	accessory.Parent = character
	part("Handle", CFrame.new(0, 5.5, 0), Vector3.new(1, 1, 1), accessory)
	local function reference()
		return root.CFrame
	end

	local id = "__Character_Dummy"
	local holder = Instance.new("Folder")
	local ok, err = xpcall(function()
		local limbs = C.FromCharacter(character, { Reference = reference })()
		assert(limbs.Shape == "Compound" and #limbs.Children == 2, "root part and accessories are excluded by default")
		assert(limbs.Children[1].Name == "Head" and limbs.Children[2].Name == "UpperTorso", "children are name-sorted")
		assert(
			(limbs.Children[1].Offset.Position - Vector3.new(0, 1.5, 0)).Magnitude < 1e-5,
			"limbs are local to the reference"
		)
		assert(
			#C.FromCharacter(character, { Reference = reference, IncludeAccessories = true })().Children == 3,
			"accessories opt in"
		)
		assert(#C.FromCharacter(character, {
			Reference = reference,
			Filter = function(p)
				return p.Name == "Head"
			end,
		})().Children == 1, "Filter overrides the default selection")
		assert(
			C.FromCharacter(Instance.new("Model"), { Reference = reference })() == nil,
			"no limbs records no collision"
		)

		-- Animated limbs: history keeps where the head was, not where it is now.
		local timeline = Chronocast:Track({
			Id = id,
			SnapshotInterval = 0.05,
			Adapter = {
				GetTransform = function()
					return root.CFrame
				end,
			},
			Collision = C.FromCharacter(character, { Reference = reference }),
		})
		local t0 = timeline:GetSnapshots()[1].Time
		head.CFrame = CFrame.new(3, 4.5, 0)
		timeline:captureSnapshot(t0 + 1)
		local shot = {
			Shape = "Ray",
			Parameters = { Origin = Vector3.new(0, 4.5, -10), Direction = Vector3.zAxis, MaxDistance = 20 },
			Filter = function(candidate)
				return candidate == timeline
			end,
		}
		local past = Chronocast:CreateContext(t0)
		local hit = past:Cast(shot)
		assert(hit and hit.Name == "Head" and math.abs(hit.Distance - 9.4) < 1e-5, "historical headshot should land")
		local now = Chronocast:CreateContext(t0 + 1)
		assert(now:Cast(shot) == nil, "the head has since moved out of the ray")

		-- Visualizer draws adornments into its own folder and cleans up.
		local visualizer = Chronocast.Debug.Visualizer({ Parent = holder, Adornee = root })
		visualizer:DrawWorldCollision(C.toWorldSpace(
			C.Compound({
				C.Box({ Size = Vector3.one }),
				C.Sphere({ Radius = 1 }),
				C.Capsule({ Radius = 1, Height = 2 }),
			}),
			CFrame.new(1, 2, 3)
		))
		assert(#visualizer.Folder:GetChildren() == 5, "box + sphere + capsule (cylinder and two caps)")
		visualizer:DrawTimeline(timeline, past)
		visualizer:DrawCast(shot, hit, past)
		visualizer:DrawOverlap(
			{ Shape = "Sphere", Parameters = { Origin = Vector3.zero, Radius = 2 } },
			past:Overlap({
				Shape = "Sphere",
				Parameters = { Origin = Vector3.new(0, 4.5, 0), Radius = 2 },
				Filter = shot.Filter,
			})
		)
		visualizer:DrawTrail(timeline, { Step = 0.25 })
		assert(#visualizer.Folder:GetChildren() > 5, "drawing should add adornments")
		visualizer:Clear()
		assert(#visualizer.Folder:GetChildren() == 0, "Clear removes every drawing")
		visualizer:Destroy()
		past:Destroy()
		now:Destroy()
	end, debug.traceback)
	Chronocast:Untrack(id)
	character:Destroy()
	holder:Destroy()
	if not ok then
		error(err, 0)
	end
end
