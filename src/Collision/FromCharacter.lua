-- Samples per-limb collision from an animated character on every capture.
-- Limb offsets are local to the character's pivot, which is the transform the
-- auto-inferred Model adapter records. Supply Reference when using another adapter.
local FromPart = require(script.Parent.FromPart)

local FromCharacter = {}

local function insideAccessory(part, character)
	local ancestor = part.Parent
	while ancestor and ancestor ~= character do
		if ancestor:IsA("Accoutrement") or ancestor:IsA("Tool") then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function defaultFilter(part, character, includeAccessories)
	if part.Name == "HumanoidRootPart" then
		return false
	end
	return includeAccessories or not insideAccessory(part, character)
end

function FromCharacter.provider(character, options)
	assert(typeof(character) == "Instance" and character:IsA("Model"), "FromCharacter requires a character Model")
	options = options or {}
	local filter = options.Filter
	local includeAccessories = options.IncludeAccessories == true
	local getReference = options.Reference or function(model)
		return model:GetPivot()
	end
	assert(filter == nil or type(filter) == "function", "FromCharacter Filter must be a function")
	assert(type(getReference) == "function", "FromCharacter Reference must be a function")

	return function()
		local reference = getReference(character)
		assert(typeof(reference) == "CFrame", "FromCharacter Reference must return a CFrame")
		local children = {}
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				local keep
				if filter then
					keep = filter(part)
				else
					keep = defaultFilter(part, character, includeAccessories)
				end
				if keep then
					local child = table.clone(FromPart.generate(part, reference))
					child.Name = part.Name
					table.insert(children, child)
				end
			end
		end
		-- A character with no eligible limbs (e.g. mid-respawn) records no collision.
		if #children == 0 then
			return nil
		end
		-- Deterministic child order: equal-distance ties resolve by limb name, then position.
		table.sort(children, function(a, b)
			if a.Name ~= b.Name then
				return a.Name < b.Name
			end
			local pa, pb = a.Offset.Position, b.Offset.Position
			if pa.X ~= pb.X then
				return pa.X < pb.X
			end
			if pa.Y ~= pb.Y then
				return pa.Y < pb.Y
			end
			return pa.Z < pb.Z
		end)
		return { Shape = "Compound", Offset = CFrame.new(), Children = children }
	end
end

return FromCharacter
