-- lib — shared helpers: click, module requires, unit conversions, positions
local S = getgenv().Astolfo
local Workspace = S.Workspace
local ReplicatedStorage = S.ReplicatedStorage
local VirtualInputManager = S.VirtualInputManager
local player = S.player

function S.click(x, y)
	if type(mouse1click) == "function" then
		pcall(mouse1click)
		return true
	end
	if type(mouse1press) == "function" and type(mouse1release) == "function" then
		pcall(mouse1press)
		task.wait(0.03)
		pcall(mouse1release)
		return true
	end
	local ok = pcall(function()
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
	end)
	return ok
end

function S.requireShared(name)
	local node = ReplicatedStorage:FindFirstChild("Shared")
	if not node then
		return nil
	end
	for part in name:gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	if not node then
		return nil
	end
	local ok, res = pcall(require, node)
	return ok and typeof(res) == "table" and res or nil
end

S.physics = S.requireShared("MCPhysics")
S.aimAssist = S.requireShared("AimAssist")
S.inputs = S.requireShared("Net/Inputs")
S.kbDelay = S.requireShared("KbDelay")
S.simulation = S.requireShared("Net/Simulation")

S.SPB = (S.physics and S.physics.Constants and S.physics.Constants.STUDS_PER_BLOCK) or 3.5714
do
	local cfg = S.requireShared("Config")
	S.mapOrigin = (cfg and cfg.Map and cfg.Map.Origin) or Vector3.zero
end

-- The sim keeps the real position in the player's attributes — in BLOCK units.
-- Render models are in studs: studs = blocks * SPB + mapOrigin.
function S.selfPos()
	local x = player:GetAttribute("X")
	local y = player:GetAttribute("Y")
	local z = player:GetAttribute("Z")
	if x then
		return Vector3.new(x, y or 0, z or 0) * S.SPB + S.mapOrigin
	end
	local camera = Workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.zero
end

function S.findHead(model)
	if not model then
		return nil
	end
	local named = model:FindFirstChild("Head")
	if named and named:IsA("BasePart") then
		return named
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name:find("Head") then
			return p
		end
	end
	return nil
end

function S.targetAttr(m, name)
	local id = m.Name:match("MCBody%s+(%S+)$")
	local mcPlayers = Workspace:FindFirstChild("MCPlayers")
	local pinst = id and mcPlayers and mcPlayers:FindFirstChild(id)
	local v = pinst and pinst:GetAttribute(name)
	if v == nil and m:FindFirstChild("Info") then
		v = m.Info:GetAttribute(name)
	end
	return v
end

function S.targetHealth(m)
	return S.targetAttr(m, "Health")
end

S.hookStatus = {}
