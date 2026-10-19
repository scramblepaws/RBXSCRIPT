-- ProbeDeep — reverse-engineering pass:
--   1) workspace structure + find your avatar (or prove it doesn't exist)
--   2) camera override test: does a written rotation persist or get overwritten?
--   3) hook the game's attack/input/simulation functions and capture REAL call
--      signatures while you click bots (10s window)
--   4) camera movement sampling
--   5) decompile + Konstant retry, captured fully
-- Run it, real-click a few bots during the 10s window, wiggle the mouse after.
-- Run: loadstring(game:HttpGet("<raw url>"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
print("[deep] userId=" .. tostring(player.UserId) .. " placeId=" .. tostring(game.PlaceId))

local function shortVal(v, depth, seen)
	local t = typeof(v)
	if t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:sub(1, 30) .. '"'
	elseif t == "function" then
		return "function"
	elseif t == "table" then
		if depth >= 2 then
			return "{...}"
		end
		seen = seen or {}
		if seen[v] then
			return "<cycle>"
		end
		seen[v] = true
		local parts, n = {}, 0
		for k, val in pairs(v) do
			n = n + 1
			if n > 6 then
				parts[#parts + 1] = "..."
				break
			end
			parts[#parts + 1] = tostring(k) .. "=" .. shortVal(val, depth + 1, seen)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v):sub(1, 30)
end

--------------------------------------------------------------------
-- 1) structure: top level, models with heads, player scripts
--------------------------------------------------------------------

print("[deep] === workspace top-level ===")
local names = {}
for _, c in ipairs(Workspace:GetChildren()) do
	names[#names + 1] = c.Name .. "(" .. c.ClassName .. ")"
end
print("[deep] " .. table.concat(names, ", "))

local modelsWithHead, scanned = {}, 0
local deadline = tick() + 2.5
for _, d in ipairs(Workspace:GetDescendants()) do
	scanned = scanned + 1
	if tick() > deadline then
		break
	end
	if d:IsA("Model") and d:FindFirstChild("Head") then
		local h = d:FindFirstChild("Head")
		modelsWithHead[#modelsWithHead + 1] = d:GetFullName() .. "  head@" .. tostring(h.Position)
		if #modelsWithHead >= 15 then
			break
		end
	end
end
print("[deep] scanned " .. scanned .. " descendants, models with a Head: " .. #modelsWithHead)
for _, s in ipairs(modelsWithHead) do
	print("[deep]   " .. s)
end

print("[deep] === player children ===")
if player then
	for _, c in ipairs(player:GetChildren()) do
		print("[deep]   " .. c.Name .. "(" .. c.ClassName .. ")")
	end
	print("[deep] Character: " .. tostring(player.Character))
end

local ps = player and player:FindFirstChild("PlayerScripts")
print("[deep] === PlayerScripts ===")
if ps then
	for _, c in ipairs(ps:GetChildren()) do
		print("[deep]   " .. c.Name .. "(" .. c.ClassName .. ")")
	end
end

--------------------------------------------------------------------
-- 2) camera override test
--------------------------------------------------------------------

local cam = Workspace.CurrentCamera
print("[deep] camera: " .. tostring(cam and cam.CameraType) .. " @ " .. tostring(cam and cam.CFrame.Position))
if cam and cam.CameraType == Enum.CameraType.Scriptable then
	local before = cam.CFrame
	cam.CFrame = before * CFrame.Angles(0, 0.5, 0)
	task.wait(0.15)
	local after = cam.CFrame
	local persisted = math.abs((after.Rotation.Y - before.Rotation.Y - 0.5)) < 0.05
	print("[deep] camera override test: rotation persisted after 150ms = " .. tostring(persisted))
	cam.CFrame = before
else
	print("[deep] camera override test: skipped (not scriptable)")
end

-- mouse-driving capabilities (the aim path if the camera fights us)
for _, name in ipairs({ "mousemoverel", "mousemoveabs", "getmousepos", "setmousepos", "movevector" }) do
	local f = rawget((getgenv and getgenv()) or _G, name)
	print("[deep] cap " .. name .. ": " .. tostring(type(f) == "function"))
end

--------------------------------------------------------------------
-- 3) hook the game's own functions, capture real signatures
--------------------------------------------------------------------

local function wrapTbl(tbl, key, label)
	local orig = tbl and tbl[key]
	if type(orig) ~= "function" then
		print("[deep] hook skip: " .. label .. " (not found)")
		return
	end
	local calls = 0
	tbl[key] = function(...)
		calls = calls + 1
		if calls <= 3 then
			local args, parts = { ... }, {}
			for i, a in ipairs(args) do
				if i > 4 then
					parts[#parts + 1] = "..."
					break
				end
				parts[#parts + 1] = "#" .. i .. "=" .. shortVal(a, 1)
			end
			print("[hook] " .. label .. "(" .. table.concat(parts, ", ") .. ")")
		elseif calls == 4 then
			print("[hook] " .. label .. ": more calls, logging stopped")
		end
		return orig(...)
	end
end

local physics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MCPhysics"))
local inputs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Inputs"))
local simulation = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Simulation"))

wrapTbl(physics.Combat, "clientAttack", "Combat.clientAttack")
wrapTbl(physics.Combat, "serverAttack", "Combat.serverAttack")
wrapTbl(physics.Combat, "rayHit", "Combat.rayHit")
wrapTbl(physics.Movement, "tick", "Movement.tick")
wrapTbl(inputs, "fireAttack", "Inputs.fireAttack")
wrapTbl(inputs, "fireLook", "Inputs.fireLook")
wrapTbl(inputs, "fireUseClicks", "Inputs.fireUseClicks")
wrapTbl(inputs, "fireHeld", "Inputs.fireHeld")
wrapTbl(simulation, "onHit", "Simulation.onHit")
wrapTbl(simulation, "onMeleeResult", "Simulation.onMeleeResult")
wrapTbl(simulation, "onKill", "Simulation.onKill")

print("[deep] hooks live — REAL-CLICK A FEW BOTS now (10s window)...")
task.wait(10)
print("[deep] hook window done (wrappers stay installed, they only log)")

--------------------------------------------------------------------
-- 4) camera movement sampling (who moves it, how often)
--------------------------------------------------------------------

print("[deep] camera sampling 3s — wiggle the mouse...")
local frames, moved = 0, 0
local lastC = cam and cam.CFrame
local sconn = RunService.Heartbeat:Connect(function()
	frames = frames + 1
	if cam and lastC then
		if (cam.CFrame.Position - lastC.Position).Magnitude + (cam.CFrame.Rotation - lastC.Rotation).Magnitude > 0.001 then
			moved = moved + 1
		end
	end
	lastC = cam and cam.CFrame
end)
task.wait(3)
sconn:Disconnect()
print(string.format("[deep] camera: %d/%d frames moved", moved, frames))

--------------------------------------------------------------------
-- 5) decompile + Konstant
--------------------------------------------------------------------

local dec = rawget((getgenv and getgenv()) or _G, "decompile")
if type(dec) == "function" then
	local ok, src = pcall(debug.info, dec, "s")
	print("[deep] decompile global source: " .. tostring(ok and src))
	local ok2, res = pcall(dec, ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MCPhysics"))
	if ok2 and type(res) == "string" then
		print("[deep] decompile(MCPhysics): " .. #res .. " chars:")
		print(res:sub(1, 400))
	end
end

local requestFn = (syn and syn.request) or (http and http.request) or http_request or request
if type(requestFn) == "function" and type(getscriptbytecode) == "function" then
	local okBc, bc = pcall(getscriptbytecode, ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MCPhysics"))
	if okBc and type(bc) == "string" and #bc > 0 then
		print("[deep] konstant: posting " .. #bc .. " bytes...")
		task.spawn(function()
			local okReq, res = pcall(requestFn, {
				Url = "http://api.plusgiant5.com/konstant/decompile",
				Method = "POST",
				Body = bc,
				Headers = { ["Content-Type"] = "text/plain" },
			})
			if okReq and res and res.StatusCode == 200 then
				local body = tostring(res.Body)
				print("[deep] konstant OK: " .. #body .. " chars")
				print(body:sub(1, 4000))
			else
				print("[deep] konstant failed: " .. tostring(okReq and res and (res.StatusCode or res.Body) or res))
			end
		end)
	else
		print("[deep] konstant skipped: no bytecode")
	end
else
	print("[deep] konstant skipped: no request fn")
end

print("[deep] done")
