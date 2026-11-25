-- Generates a local-space bounding box from a Model's BasePart descendants.
local FromModel = {}

function FromModel.generate(model, referenceCFrame)
	assert(model, "FromModel.generate requires a Model")
	assert(model:IsA("Model"), "FromModel.generate requires a Model")
	local reference = referenceCFrame or model:GetPivot()
	assert(typeof(reference) == "CFrame", "referenceCFrame must be a CFrame")
	local minPos = Vector3.new(math.huge, math.huge, math.huge)
	local maxPos = Vector3.new(-math.huge, -math.huge, -math.huge)
	local hasParts = false

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			hasParts = true
			local cf = reference:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local corner = cf * Vector3.new(half.X * x, half.Y * y, half.Z * z)
						minPos = Vector3.new(math.min(minPos.X, corner.X), math.min(minPos.Y, corner.Y), math.min(minPos.Z, corner.Z))
						maxPos = Vector3.new(math.max(maxPos.X, corner.X), math.max(maxPos.Y, corner.Y), math.max(maxPos.Z, corner.Z))
					end
				end
			end
		end
	end

	if not hasParts then
		return table.freeze({ Shape = "Box", Offset = CFrame.new(), Size = Vector3.new(1, 1, 1) })
	end
	local center = (minPos + maxPos) / 2
	return table.freeze({ Shape = "Box", Offset = CFrame.new(center), Size = maxPos - minPos })
end

return FromModel
