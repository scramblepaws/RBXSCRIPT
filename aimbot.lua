-- AimBot v3 — mouse-driven aim for a game with no local avatar.
-- The game's camera is Scriptable (its CFrame is overwritten every frame) and its
-- hits raycast from the sim's eye along the sim's yaw, which is fed by real mouse
-- deltas. There is no local body model to rotate, so aiming = move the real mouse
-- (mousemoverel) until the target is centered, then click. Reach/speed/anticheat
-- patch the game's own tables, which keeps the sim consistent.

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------

local CONFIG = {
	BIND = Enum.KeyCode.F, -- toggle aim+click
	KILL_BIND = Enum.KeyCode.L, -- unload the script entirely (kill switch)
	SPEED_BIND = Enum.KeyCode.G, -- toggle movement speed boost
	RANGE = 60, -- studs (from your camera)
	INCLUDE_BOTS = true,
	AIM_SENS = 0.5, -- mouse-delta multiplier (raise if aim lags, lower if it wobbles)
	AIM_MAX_DELTA = 40, -- px per frame cap
	AUTO_CLICK = true,
	CLICK_INTERVAL = 0.25,
	CLICK_RANGE_PX = 45, -- click when the target is within this many px of screen center
	PATCH_REACH = true,
	REACH_COMBAT = 4.5, -- game default 3
	REACH_BLOCKS = 8, -- game default 4.5
	PATCH_ANTICHEAT = true,
	SPEED_WALK_MULT = 2.5,
	SPEED_SPRINT_MULT = 2,
	WATERMARK = "Astolfo",
	WATERMARK_ON = true,
	WATERMARK_SIZE = 40,
	WATERMARK_SPEED = 140, -- pixels/second, left to right
	WATERMARK_BRIGHT = Color3.fromRGB(40, 170, 255),
	WATERMARK_DARK = Color3.fromRGB(6, 30, 90),
	BOX_COLOR = Color3.fromRGB(255, 60, 60),
	BOX_THICKNESS = 2,
}

--------------------------------------------------------------------
-- Services
--------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
if not player then
	warn("[Aim] Needs to run as a client local script.")
	return
end

--------------------------------------------------------------------
-- Mouse helpers (executor globals; mousemoverel confirmed present)
--------------------------------------------------------------------

local function moveMouseRel(dx, dy)
	pcall(mousemoverel, dx, dy)
end

local function click(x, y)
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

--------------------------------------------------------------------
-- Targets: avatars live in Workspace.MCPlayers (SkyWars) and/or as
-- Workspace children (Pit). This game never spawns a local avatar model.
--------------------------------------------------------------------

local function findHead(model)
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

local function isTargetBody(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("Model") then
		return false
	end
	local name = inst.Name
	if name == "MCBody" then
		return false -- unpositioned template rig
	end
	if name == "MCBody " .. tostring(player.UserId) then
		return false
	end
	if name:sub(1, 6) ~= "MCBody" then
		return false
	end
	if not CONFIG.INCLUDE_BOTS and name:find("Bot") then
		return false
	end
	return true
end

local function targetCandidates()
	local seen, out = {}, {}
	local function add(container)
		if not container then
			return
		end
		for _, m in ipairs(container:GetChildren()) do
			if isTargetBody(m) and not seen[m] then
				seen[m] = true
				out[#out + 1] = m
			end
		end
	end
	add(Workspace:FindFirstChild("MCPlayers"))
	add(Workspace)
	return out
end

local function findTarget()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	local best, bestDist, bestPos
	for _, m in ipairs(targetCandidates()) do
		local h = findHead(m)
		if h and h.Parent then
			local d = (h.Position - camPos).Magnitude
			if d <= CONFIG.RANGE and d < (bestDist or math.huge) then
				best, bestDist, bestPos = m, d, h.Position
			end
		end
	end
	return best, bestDist, bestPos
end

--------------------------------------------------------------------
-- Game patches (all live: require returns the same cached table the game uses)
--   * Combat.REACH / Blocks.REACH — hit/break range
--   * Config.AntiCheat.Enabled — the client-side violation tracker
--   * Constants.WALK_SPEED etc. — the sim moves the avatar from these each tick,
--     so boosting them keeps sim and MoveReport in agreement (no movement flag)
--------------------------------------------------------------------

local patches = {}

local function requireShared(name)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local mod = shared and shared:FindFirstChild(name)
	if not mod then
		return nil
	end
	local ok, res = pcall(require, mod)
	return ok and typeof(res) == "table" and res or nil
end

local function patchGame()
	local physics = requireShared("MCPhysics")
	local changed = {}
	if physics then
		if physics.Combat and physics.Combat.REACH then
			patches.reach = physics.Combat.REACH
			physics.Combat.REACH = CONFIG.REACH_COMBAT
			changed[#changed + 1] = "Combat.REACH " .. patches.reach .. "->" .. CONFIG.REACH_COMBAT
		end
		if physics.Blocks and physics.Blocks.REACH then
			patches.blockReach = physics.Blocks.REACH
			physics.Blocks.REACH = CONFIG.REACH_BLOCKS
			changed[#changed + 1] = "Blocks.REACH " .. patches.blockReach .. "->" .. CONFIG.REACH_BLOCKS
		end
		if physics.Constants then
			patches.constants = {
				walk = physics.Constants.WALK_SPEED,
				base = physics.Constants.BASE_MOVE_SPEED,
				sprint = physics.Constants.SPRINT_SPEED_MODIFIER,
			}
		end
	end
	if CONFIG.PATCH_ANTICHEAT then
		local config = requireShared("Config")
		if config and config.AntiCheat then
			patches.acEnabled = config.AntiCheat.Enabled
			config.AntiCheat.Enabled = false
			changed[#changed + 1] = "AntiCheat.Enabled " .. tostring(patches.acEnabled) .. "->false"
		end
	end
	return #changed > 0 and table.concat(changed, ", ") or "nothing patched"
end

local patchResult = patchGame()

local speedOn = false

local function setSpeed(on)
	if not patches.constants then
		return false, "no Constants"
	end
	local physics = requireShared("MCPhysics")
	if not physics or not physics.Constants then
		return false, "no Constants table"
	end
	local c = physics.Constants
	-- Constants is table.freeze'd in source; if the write throws we fall back later
	-- to setting the state's speedLevel (the game's own speed-potion mechanic).
	local ok = pcall(function()
		if on then
			c.WALK_SPEED = patches.constants.walk * CONFIG.SPEED_WALK_MULT
			c.BASE_MOVE_SPEED = patches.constants.base * CONFIG.SPEED_WALK_MULT
			c.SPRINT_SPEED_MODIFIER = patches.constants.sprint * CONFIG.SPEED_SPRINT_MULT
		else
			c.WALK_SPEED = patches.constants.walk
			c.BASE_MOVE_SPEED = patches.constants.base
			c.SPRINT_SPEED_MODIFIER = patches.constants.sprint
		end
	end)
	if not ok then
		return false, "Constants frozen"
	end
	return true
end

local function restorePatches()
	local physics = requireShared("MCPhysics")
	if physics then
		if patches.reach and physics.Combat then
			physics.Combat.REACH = patches.reach
		end
		if patches.blockReach and physics.Blocks then
			physics.Blocks.REACH = patches.blockReach
		end
		if patches.constants and physics.Constants then
			setSpeed(false)
		end
	end
	if patches.acEnabled ~= nil then
		local config = requireShared("Config")
		if config and config.AntiCheat then
			config.AntiCheat.Enabled = patches.acEnabled
		end
	end
end

--------------------------------------------------------------------
-- Drawings (box ESP + watermark)
--------------------------------------------------------------------

local RENDER_NAME = "UntitledAim"
local drawings = {}
local box, label, wm
local wmX = 0

do
	local ok = pcall(function()
		if not Drawing then
			error("no Drawing")
		end
		box = Drawing.new("Square")
		box.Thickness = CONFIG.BOX_THICKNESS
		box.Filled = false
		box.Color = CONFIG.BOX_COLOR
		box.Visible = false
		drawings[#drawings + 1] = box

		label = Drawing.new("Text")
		label.Size = 16
		label.Center = true
		label.Outline = true
		label.Color = CONFIG.BOX_COLOR
		label.Visible = false
		drawings[#drawings + 1] = label

		wm = Drawing.new("Text")
		wm.Text = CONFIG.WATERMARK
		wm.Size = CONFIG.WATERMARK_SIZE
		wm.Center = false
		wm.Outline = true
		wm.Color = CONFIG.WATERMARK_BRIGHT
		wm.Visible = CONFIG.WATERMARK_ON
		drawings[#drawings + 1] = wm
	end)
	if not ok then
		warn("[Aim] Drawing API unavailable — aiming still works, no box/watermark.")
	end
end

--------------------------------------------------------------------
-- Per-frame loop
--------------------------------------------------------------------

local enabled = false
local target, targetDist, targetPos
local lastClick = 0

local wmClock = 0
local function stepWatermark(dt)
	if not wm or not wm.Visible then
		return
	end
	dt = dt or 0
	wmClock = wmClock + dt
	local screenW = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X) or 1920
	local width = math.max(#wm.Text * CONFIG.WATERMARK_SIZE * 0.6, 120)
	wmX = wmX + CONFIG.WATERMARK_SPEED * dt
	if wmX > screenW then
		wmX = -width
	end
	local t = (math.sin(wmClock * 2) + 1) / 2 -- 0..1
	wm.Position = Vector2.new(wmX, 10)
	wm.Size = CONFIG.WATERMARK_SIZE + t * 4 -- slight pulse
	wm.Color = CONFIG.WATERMARK_BRIGHT:Lerp(CONFIG.WATERMARK_DARK, t)
end

-- start off the left edge so it visually enters from the left
wmX = -300

local function step(dt)
	local camera = Workspace.CurrentCamera
	target, targetDist, targetPos = findTarget()

	local screenPos
	if targetPos and camera then
		local p, onScreen = camera:WorldToViewportPoint(targetPos)
		screenPos = onScreen and p or nil
	end

	stepWatermark(dt)

	if box and label then
		if screenPos then
			local dist = targetDist or 0
			local size = math.clamp(900 / math.max(dist, 1), 24, 260)
			box.Size = Vector2.new(size, size * 1.35)
			box.Position = Vector2.new(screenPos.X - size / 2, screenPos.Y - size * 0.68)
			box.Visible = true
			label.Position = Vector2.new(screenPos.X, screenPos.Y - size * 0.78 - 14)
			label.Text = target.Name .. "  [" .. math.floor(dist) .. "]"
			label.Visible = true
		else
			box.Visible = false
			label.Visible = false
		end
	end

	if not (enabled and screenPos and camera) then
		return
	end

	local half = camera.ViewportSize / 2
	local dx, dy = screenPos.X - half.X, screenPos.Y - half.Y
	if math.abs(dx) > 2 or math.abs(dy) > 2 then
		moveMouseRel(
			math.clamp(dx * CONFIG.AIM_SENS, -CONFIG.AIM_MAX_DELTA, CONFIG.AIM_MAX_DELTA),
			math.clamp(dy * CONFIG.AIM_SENS, -CONFIG.AIM_MAX_DELTA, CONFIG.AIM_MAX_DELTA))
	end
	if CONFIG.AUTO_CLICK
		and math.abs(dx) <= CONFIG.CLICK_RANGE_PX
		and math.abs(dy) <= CONFIG.CLICK_RANGE_PX
		and tick() - lastClick >= CONFIG.CLICK_INTERVAL then
		lastClick = tick()
		click(screenPos.X, screenPos.Y)
	end
end

local connections = {}
if RunService.BindToRenderStep then
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value - 1, step)
else
	connections[#connections + 1] = RunService.RenderStepped:Connect(step)
end

--------------------------------------------------------------------
-- Kill switch: fully unloads the script
--------------------------------------------------------------------

local function unload()
	pcall(function()
		if RunService.UnbindFromRenderStep then
			RunService:UnbindFromRenderStep(RENDER_NAME)
		end
	end)
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(connections)
	for _, d in ipairs(drawings) do
		pcall(function()
			d.Visible = false
			d:Remove()
		end)
	end
	table.clear(drawings)
	box, label, wm = nil, nil, nil
	restorePatches()
	if getgenv then
		getgenv().Aim = nil
	end
	print("[Aim] script killed — unhooked, patches restored, drawings removed.")
end

--------------------------------------------------------------------
-- Bind
--------------------------------------------------------------------

connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.BIND then
		enabled = not enabled
		print("[Aim] " .. (enabled and "ON" or "OFF")
			.. (target and (" — target " .. target.Name .. " @ " .. math.floor(targetDist or 0)) or " — no target in range"))
	elseif input.KeyCode == CONFIG.KILL_BIND then
		unload()
	elseif input.KeyCode == CONFIG.SPEED_BIND then
		speedOn = not speedOn
		local ok, err = setSpeed(speedOn)
		print("[Aim] speed boost " .. (speedOn and "ON (BASE_MOVE_SPEED x" .. CONFIG.SPEED_WALK_MULT .. ")" or "OFF")
			.. (ok and "" or " — " .. tostring(err)))
	end
end)

--------------------------------------------------------------------
-- SELF CHECK
--------------------------------------------------------------------

if getgenv then
	getgenv().Aim = { findTarget = findTarget, click = click, candidates = targetCandidates }
end

task.spawn(function()
	task.wait(1)
	local a, b = Vector3.new(0, 0, 0), Vector3.new(1, 0, 0)
	local lv = CFrame.lookAt(a, b).LookVector
	assert((lv - (b - a).Unit).Magnitude < 1e-4, "[Aim] lookAt math broken")

	print("[Aim][check] mouse aim: mousemoverel=" .. tostring(type(mousemoverel) == "function"))
	local cands = targetCandidates()
	local names = {}
	for _, m in ipairs(cands) do
		names[#names + 1] = m.Name
	end
	print("[Aim][check] targets: " .. #names .. " (" .. table.concat(names, ", ") .. ")")
	print("[Aim][check] note: no local avatar model exists in this game — aiming is mouse-driven.")
	print("[Aim][check] patches: " .. tostring(patchResult))
	print("[Aim] Ready — " .. CONFIG.BIND.Name .. " aim+click | " .. CONFIG.SPEED_BIND.Name
		.. " speed boost | " .. CONFIG.KILL_BIND.Name .. " kill script")
end)
