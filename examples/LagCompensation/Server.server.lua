-- Server half of the lag-compensation example. Place this Script and ShotValidator
-- together in ServerScriptService, with Chronocast in ReplicatedStorage.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chronocast = require(ReplicatedStorage.Chronocast)
local ShotValidator = require(script.Parent.ShotValidator)

local FIRE_INTERVAL = 0.1 -- seconds between accepted shots per player
local HEAD_DAMAGE, BODY_DAMAGE = 50, 20

local remote = Instance.new("RemoteEvent")
remote.Name = "ChronocastShot"
remote.Parent = ReplicatedStorage

local validator = ShotValidator.new(Chronocast)
local timelineOf = {} -- Player -> Timeline
local playerOf = {} -- Timeline -> Player
local lastShot = {} -- Player -> server time of last accepted shot

local function untrack(player)
	local timeline = timelineOf[player]
	if timeline then
		playerOf[timeline] = nil
		timelineOf[player] = nil
		timeline:Destroy()
	end
end

local function track(player, character)
	untrack(player)
	-- Auto-inference records character:GetPivot(); FromCharacter limbs are local to the same pivot.
	character:WaitForChild("HumanoidRootPart")
	if character.PrimaryPart == nil or not character:IsDescendantOf(workspace) then
		return
	end
	local timeline = Chronocast:Track({
		Id = "Player_" .. player.UserId,
		Instance = character,
		Collision = Chronocast.Collision.FromCharacter(character),
	})
	timelineOf[player] = timeline
	playerOf[timeline] = player
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		track(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		untrack(player)
	end)
	if player.Character then
		track(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	untrack(player)
	lastShot[player] = nil
end)

remote.OnServerEvent:Connect(function(player, origin, direction, clientTime)
	local now = Chronocast:GetServerTime()
	if lastShot[player] and now - lastShot[player] < FIRE_INTERVAL then
		return
	end
	local shooter = timelineOf[player]
	if not shooter then
		return
	end
	lastShot[player] = now
	local hit = validator:Validate(shooter, { Origin = origin, Direction = direction, ClientTime = clientTime }, now)
	if not hit then
		return -- the second return value says why: Miss, OriginMismatch, MalformedShot, ...
	end
	local victim = playerOf[hit.Timeline]
	local humanoid = victim and victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(hit.Name == "Head" and HEAD_DAMAGE or BODY_DAMAGE)
	end
end)
