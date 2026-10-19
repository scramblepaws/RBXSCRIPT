-- AimBot — face the nearest player with your head, and click to attack.
-- ponytail: this game has no Humanoids and clicking fires no remote (probed), so hits are
-- resolved by the game's own controller when it sees a real mouse click. Aiming = set your
-- head CFrame toward the target each frame; attacking = synthesize a real click.

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------

local CONFIG = {
	BIND = Enum.KeyCode.F, -- toggle
	RANGE = 60, -- studs
	INCLUDE_BOTS = true, -- `MCBody Bot####` models are valid targets
	LOCAL_MODEL_NAME = "MCBody", -- your own avatar model (others are `MCBody <id>`)
	HEAD_RUN_PRIORITY = Enum.RenderPriority.Last.Value - 1, -- run after everything so the turn sticks
	AIM_WHOLE_BODY = true, -- yaw the body too, not just the head
	AUTO_CLICK = true, -- click at the target while aiming
	CLICK_INTERVAL = 0.2, -- seconds between clicks
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

local player = Players.LocalPlayer
if not player then
	warn("[Aim] Needs to run as a client local script.")
	return
end

--------------------------------------------------------------------
-- Finding your own model + head
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
	local best, bestY = nil, -math.huge
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Position.Y > bestY then
			best, bestY = p, p.Position.Y
		end
	end
	return best
end

local function localModel()
	return Workspace:FindFirstChild(CONFIG.LOCAL_MODEL_NAME)
end

local ROOT_NAMES = { "Torso", "Root", "RootPart", "UpperTorso", "HumanoidRootPart", "Body", "Chest" }

-- the part that carries the avatar's yaw (torso-ish), if any
local function findRoot(model)
	if not model then
		return nil
	end
	local pp = model.PrimaryPart
	if pp and pp:IsA("BasePart") then
		return pp
	end
	for _, n in ipairs(ROOT_NAMES) do
		local p = model:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

--------------------------------------------------------------------
-- Target selection (other `MCBody*` models)
--------------------------------------------------------------------

local function isTargetBody(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("Model") then
		return false
	end
	if inst.Name == CONFIG.LOCAL_MODEL_NAME then
		return false
	end
	if inst.Name:sub(1, 6) ~= "MCBody" then
		return false
	end
	if not CONFIG.INCLUDE_BOTS and inst.Name:find("Bot") then
		return false
	end
	return true
end

local function findTarget()
	local myHead = findHead(localModel())
	local myPos = myHead and myHead.Position or Vector3.zero
	local best, bestDist, bestHead
	for _, m in ipairs(Workspace:GetChildren()) do
		if isTargetBody(m) then
			local h = findHead(m)
			if h and h.Parent then
				local d = (h.Position - myPos).Magnitude
				if d <= CONFIG.RANGE and d < (bestDist or math.huge) then
					best, bestDist, bestHead = m, d, h
				end
			end
		end
	end
	return best, bestDist, bestHead
end

--------------------------------------------------------------------
-- The aim function
--------------------------------------------------------------------

-- Rotate `part` (your head) so its front faces `targetHead`, keeping its position.
local function AimPart(part, targetHead)
	if not part or not part.Parent or not targetHead or not targetHead.Parent then
		return false
	end
	part.CFrame = CFrame.lookAt(part.Position, targetHead.Position)
	return true
end

local function AimAt(target)
	return AimPart(findHead(localModel()), findHead(target))
end

-- Turn your whole avatar toward `targetHead`: head looks fully, body yaws (keeps it upright).
local function AimModel(model, targetHead)
	if not model or not targetHead or not targetHead.Parent then
		return false
	end
	local did = false
	local head = findHead(model)
	if head and head.Parent then
		head.CFrame = CFrame.lookAt(head.Position, targetHead.Position)
		did = true
	end
	if CONFIG.AIM_WHOLE_BODY then
		local root = findRoot(model)
		if root and root.Parent and root ~= head then
			local dir = targetHead.Position - root.Position
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 0.01 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
				did = true
			end
		end
	end
	return did
end

--------------------------------------------------------------------
-- Clicking (attack)
--------------------------------------------------------------------

local VirtualInputManager = game:GetService("VirtualInputManager")

-- fire a real left click; prefers executor mouse helpers, falls back to VIM.
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

-- exported for manual use
if getgenv then
	getgenv().Aim = { AimPart = AimPart, AimAt = AimAt, AimModel = AimModel, findTarget = findTarget, findHead = findHead, findRoot = findRoot, click = click }
end

--------------------------------------------------------------------
-- Box ESP
--------------------------------------------------------------------

local RENDER_NAME = "UntitledAim"
local box, label
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
		label = Drawing.new("Text")
		label.Size = 16
		label.Center = true
		label.Outline = true
		label.Color = CONFIG.BOX_COLOR
		label.Visible = false
	end)
	if not ok then
		warn("[Aim] Drawing API unavailable — aiming still works, no box.")
	end
end

--------------------------------------------------------------------
-- Per-frame loop
--------------------------------------------------------------------

local enabled = false
local target, targetHead, targetDist
local lastClick = 0
local clickCount = 0

local function step()
	local camera = Workspace.CurrentCamera
	target, targetDist, targetHead = findTarget()

	local screenPos
	if targetHead and camera then
		local p, onScreen = camera:WorldToViewportPoint(targetHead.Position)
		screenPos = onScreen and p or nil
	end

	if enabled and targetHead then
		AimModel(localModel(), targetHead)
		if CONFIG.AUTO_CLICK and tick() - lastClick >= CONFIG.CLICK_INTERVAL then
			lastClick = tick()
			local cx, cy = (camera and camera.ViewportSize.X / 2) or 0, (camera and camera.ViewportSize.Y / 2) or 0
			if screenPos then
				cx, cy = screenPos.X, screenPos.Y
			end
			click(cx, cy)
			clickCount = clickCount + 1
		end
	end

	if not (box and label) then
		return
	end
	if not target or not targetHead or not screenPos then
		box.Visible = false
		label.Visible = false
		return
	end
	local dist = targetDist or 0
	local size = math.clamp(900 / math.max(dist, 1), 24, 260)
	box.Size = Vector2.new(size, size * 1.35)
	box.Position = Vector2.new(screenPos.X - size / 2, screenPos.Y - size * 0.68)
	box.Visible = true
	label.Position = Vector2.new(screenPos.X, screenPos.Y - size * 0.78 - 14)
	label.Text = target.Name .. "  [" .. math.floor(dist) .. "]"
	label.Visible = true
end

if RunService.BindToRenderStep then
	RunService:BindToRenderStep(RENDER_NAME, CONFIG.HEAD_RUN_PRIORITY, step)
else
	RunService.RenderStepped:Connect(step)
end

--------------------------------------------------------------------
-- Bind
--------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.BIND then
		enabled = not enabled
		print("[Aim] " .. (enabled and "ON" or "OFF")
			.. (target and (" — target " .. target.Name .. " @ " .. math.floor(targetDist or 0)) or " — no target in range"))
	end
end)

--------------------------------------------------------------------
-- SELF CHECK
--------------------------------------------------------------------

task.spawn(function()
	task.wait(1)
	local a, b = Vector3.new(0, 0, 0), Vector3.new(1, 0, 0)
	local lv = CFrame.lookAt(a, b).LookVector
	assert((lv - (b - a).Unit).Magnitude < 1e-4, "[Aim] lookAt math broken")

	local model = localModel()
	local head = findHead(model)
	print("[Aim][check] own model: " .. (model and model.Name or "NOT FOUND")
		.. "  head: " .. (head and (head.Name .. " @" .. tostring(head.Position)) or "NOT FOUND"))
	local names = {}
	for _, m in ipairs(Workspace:GetChildren()) do
		if isTargetBody(m) then
			names[#names + 1] = m.Name
		end
	end
	print("[Aim][check] targets: " .. #names .. " (" .. table.concat(names, ", ") .. ")")
	-- model anatomy, so we can see the real part names/positions
	local parts, shown = {}, 0
	for _, p in ipairs(model and model:GetDescendants() or {}) do
		if p:IsA("BasePart") and shown < 12 then
			shown = shown + 1
			parts[#parts + 1] = p.Name .. "@" .. tostring(p.Position)
		end
	end
	print("[Aim][check] parts: " .. (shown > 0 and table.concat(parts, " ") or "NONE"))
	print("[Aim][check] root: " .. (findRoot(model) and findRoot(model).Name or "NOT FOUND")
		.. "  primary: " .. (model and model.PrimaryPart and model.PrimaryPart.Name or "nil"))
	print("[Aim][check] clicker: mouse1click=" .. tostring(type(mouse1click) == "function")
		.. " mouse1press=" .. tostring(type(mouse1press) == "function") .. " vim=true")
	print("[Aim] Ready — press " .. CONFIG.BIND.Name .. " to toggle aim+click.")
end)
