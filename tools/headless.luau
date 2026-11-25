-- Headless test runner: lune run tools/headless.luau [suite-name-filter | --bench]
-- Mirrors the Argon tree as Lune Instances and runs every spec that does not
-- need a live Heartbeat. Studio remains the authority for Scheduling.spec.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local LIVE_ONLY = { ["Scheduling.spec"] = true }

local sources = {}

local function mirror(path, name, parent)
	if fs.isDir(path) then
		local initPath = path .. "/init.lua"
		local node
		if fs.isFile(initPath) then
			node = roblox.Instance.new("ModuleScript")
			sources[node] = { Path = initPath, Source = fs.readFile(initPath) }
		else
			node = roblox.Instance.new("Folder")
		end
		node.Name = name
		node.Parent = parent
		for _, entry in fs.readDir(path) do
			if entry ~= "init.lua" then
				local childPath = path .. "/" .. entry
				if fs.isDir(childPath) then
					mirror(childPath, entry, node)
				elseif string.match(entry, "%.lua$") then
					mirror(childPath, (string.gsub(entry, "%.lua$", "")), node)
				end
			end
		end
		return node
	end
	local node = roblox.Instance.new("ModuleScript")
	node.Name = name
	node.Parent = parent
	sources[node] = { Path = path, Source = fs.readFile(path) }
	return node
end

-- Controllable clock and Heartbeat so specs can drive capture deterministically.
local clock = 1000
local heartbeatListeners = {}
local Heartbeat = {}
function Heartbeat:Connect(callback)
	local connection = { Connected = true }
	heartbeatListeners[connection] = callback
	function connection:Disconnect()
		self.Connected = false
		heartbeatListeners[self] = nil
	end
	return connection
end

local Headless = {}
function Headless.setTime(time)
	clock = time
end
function Headless.getTime()
	return clock
end
function Headless.step(dt)
	clock += dt or 1 / 60
	for _, callback in heartbeatListeners do
		callback(dt or 1 / 60)
	end
end

local replicatedStorage = roblox.Instance.new("Folder")
replicatedStorage.Name = "ReplicatedStorage"
local serverStorage = roblox.Instance.new("Folder")
serverStorage.Name = "ServerStorage"
local workspaceStub = {
	Terrain = roblox.Instance.new("Folder"),
	GetServerTimeNow = function()
		return clock
	end,
}
local services = {
	Workspace = workspaceStub,
	RunService = {
		Heartbeat = Heartbeat,
		IsRunning = function()
			return true
		end,
	},
	ReplicatedStorage = replicatedStorage,
	ServerStorage = serverStorage,
}
local game = setmetatable({
	GetService = function(_, name)
		return assert(services[name], "Unsupported headless service: " .. name)
	end,
	Headless = Headless,
}, { __index = services })

mirror("src", "Chronocast", replicatedStorage)
local tests = mirror("tests", "ChronocastTests", serverStorage)
mirror("examples", "ChronocastExamples", serverStorage)

local loaded = {}
local function requireModule(module)
	if type(module) == "string" then
		return require(module)
	end
	if loaded[module] ~= nil then
		return loaded[module]
	end
	local entry = assert(sources[module], "Not a mirrored ModuleScript: " .. tostring(module))
	local chunk = luau.load(entry.Source, {
		debugName = entry.Path,
		environment = {
			script = module,
			require = requireModule,
			game = game,
			workspace = workspaceStub,
			task = task,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Instance = roblox.Instance,
			Enum = roblox.Enum,
		},
	})
	local result = chunk()
	loaded[module] = result
	return result
end

local filter = process.args[1]
if filter == "--bench" then
	requireModule(tests:FindFirstChild("Benchmark"))()
	process.exit(0)
end
local suites = {}
for _, child in tests:GetChildren() do
	if string.match(child.Name, "%.spec$") and not LIVE_ONLY[child.Name] then
		if not filter or string.find(child.Name, filter, 1, true) then
			table.insert(suites, child)
		end
	end
end
table.sort(suites, function(a, b)
	return a.Name < b.Name
end)

local failed = 0
for _, suite in suites do
	local ok, err = xpcall(function()
		return requireModule(suite)()
	end, debug.traceback)
	if ok then
		print("PASS " .. suite.Name)
	else
		failed += 1
		print("FAIL " .. suite.Name .. "\n" .. tostring(err))
	end
end
print(string.format("%d/%d suites passed (skipped live-only: %s)", #suites - failed, #suites, "Scheduling.spec"))
process.exit(failed == 0 and 0 or 1)
