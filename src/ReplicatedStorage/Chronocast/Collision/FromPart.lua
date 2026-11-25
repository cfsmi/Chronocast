-- Generates local-space collision from a BasePart.
local FromPart = {}

local function freeze(definition)
	return table.freeze(definition)
end

function FromPart.generate(part, referenceCFrame)
	assert(part, "FromPart.generate requires a BasePart")
	assert(part:IsA("BasePart"), "FromPart.generate requires a BasePart")
	local reference = referenceCFrame or part.CFrame
	assert(typeof(reference) == "CFrame", "referenceCFrame must be a CFrame")
	local localOffset = reference:ToObjectSpace(part.CFrame)
	local size = part.Size

	-- Shape is only available on ordinary Parts; MeshPart and other BaseParts
	-- must safely fall back to their oriented bounding box.
	local ok, shape = pcall(function()
		return part.Shape
	end)
	if ok and shape == Enum.PartType.Ball then
		return freeze({ Shape = "Sphere", Offset = localOffset, Radius = math.max(size.X, size.Y, size.Z) / 2 })
	end
	-- Cylinders use their oriented bounds: a capsule either protrudes beyond
	-- the cylinder ends or omits its rim. Exact cylinders are not a primitive.
	return freeze({ Shape = "Box", Offset = localOffset, Size = size })
end

return FromPart
