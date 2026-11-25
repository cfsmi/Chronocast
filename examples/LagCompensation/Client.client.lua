-- Client half of the lag-compensation example. Place this LocalScript in
-- StarterPlayerScripts. Click to fire a hitscan shot from your head toward the mouse.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local remote = ReplicatedStorage:WaitForChild("ChronocastShot")
local player = Players.LocalPlayer

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head then
		return
	end
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local aim = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local target = aim.Origin + aim.Direction * 500
	-- GetServerTimeNow is the client's estimate of the shared server clock.
	remote:FireServer(head.Position, target - head.Position, workspace:GetServerTimeNow())
end)
