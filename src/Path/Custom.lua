-- Chronocast v2 - Custom Path
--
-- Allows developers to define custom paths by providing a Sample function.

local Custom = {}

--- Creates a custom path from user-provided sample function.
--- @param params { Sample: fun(self: table, alpha: number): CFrame, Length: fun(self: table): number?, Intervals: number? }
--- @return table
function Custom.new(params)
	assert(params, "Custom path requires parameters")
	assert(params.Sample, "Custom path requires a Sample function")

	local path = {
		_sample = params.Sample,
		_length = params.Length,
		Intervals = params.Intervals or params.Samples or 10, -- Samples is the deprecated name
	}

	function path:Sample(alpha)
		return self._sample(self, alpha)
	end

	if path._length then
		function path:Length()
			return self._length(self)
		end
	end

	return path
end

return Custom
