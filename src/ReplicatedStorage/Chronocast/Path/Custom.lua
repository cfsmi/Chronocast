-- Chronocast v2 - Custom Path
--
-- Allows developers to define custom paths by providing a Sample function.

local Custom = {}

--- Creates a custom path from user-provided sample function.
--- @param params { Sample: fun(self: table, alpha: number): CFrame, Length: fun(self: table): number?, Samples: number? }
--- @return table
function Custom.new(params)
	assert(params, "Custom path requires parameters")
	assert(params.Sample, "Custom path requires a Sample function")

	local self = {
		_sample = params.Sample,
		_length = params.Length,
		Samples = params.Samples or 10,
	}

	function self:Sample(alpha)
		return self._sample(self, alpha)
	end

	if self._length then
		function self:Length()
			return self._length(self)
		end
	end

	return self
end

return Custom