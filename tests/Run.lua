-- Invoke from the server Command Bar during Play:
-- require(game.ServerStorage.ChronocastTests.Run)()
return function()
	assert(game:GetService("RunService"):IsRunning(), "Start Play before running Chronocast tests")
	local results = {}
	local suites = {}
	for _, child in ipairs(script.Parent:GetChildren()) do
		if child:IsA("ModuleScript") and string.match(child.Name, "%.spec$") then
			table.insert(suites, child)
		end
	end
	table.sort(suites, function(a, b)
		return a.Name < b.Name
	end)
	assert(#suites > 0, "No regression suites synced")
	for _, suite in ipairs(suites) do
		local ok, result = xpcall(function()
			return require(suite)()
		end, debug.traceback)
		table.insert(results, { Name = suite.Name, Passed = ok, Detail = tostring(result) })
		if ok then
			print("Chronocast PASS: " .. suite.Name)
		else
			warn("Chronocast FAIL: " .. suite.Name .. "\n" .. tostring(result))
		end
	end
	local passed = 0
	for _, result in ipairs(results) do
		if result.Passed then
			passed += 1
		end
	end
	return { Passed = passed, Total = #results, Results = results }
end
