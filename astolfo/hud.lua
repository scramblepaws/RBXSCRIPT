-- hud — "astolfo" chroma-wave watermark, active module list, TargetHUD
local S = getgenv().Astolfo
local Workspace = S.Workspace

local wmPanel
local wmLetters = {}
local moduleTexts
local hudPanel, hudName, hudHpText, hudBarBg, hudBarFill, hudDist

do
	local ok = pcall(function()
		if not Drawing then
			error("no Drawing")
		end
		wmPanel = Drawing.new("Square")
		wmPanel.Filled = true
		wmPanel.Color = Color3.fromRGB(10, 10, 10)
		wmPanel.Transparency = 0.5
		wmPanel.Visible = S.FEATURES.watermark
		S.drawings[#S.drawings + 1] = wmPanel

		-- "astolfo" letter by letter so the pink->lavender wave can flow across it
		for i = 1, #S.WATERMARK_TEXT do
			local d = Drawing.new("Text")
			d.Text = S.WATERMARK_TEXT:sub(i, i)
			d.Size = 26
			d.Outline = true
			d.Color = Color3.fromRGB(255, 158, 208)
			d.Position = Vector2.new(10 + (i - 1) * 16, 8)
			d.Visible = S.FEATURES.watermark
			S.drawings[#S.drawings + 1] = d
			wmLetters[#wmLetters + 1] = d
		end

		moduleTexts = {}
		for _ = 1, 12 do
			local d = Drawing.new("Text")
			d.Size = 15
			d.Outline = true
			d.Visible = false
			S.drawings[#S.drawings + 1] = d
			moduleTexts[#moduleTexts + 1] = d
		end

		hudPanel = Drawing.new("Square")
		hudPanel.Filled = true
		hudPanel.Color = Color3.fromRGB(8, 8, 12)
		hudPanel.Transparency = 0.4
		hudPanel.Visible = false
		S.drawings[#S.drawings + 1] = hudPanel

		hudName = Drawing.new("Text")
		hudName.Size = 15
		hudName.Outline = true
		hudName.Color = Color3.fromRGB(240, 240, 245)
		hudName.Visible = false
		S.drawings[#S.drawings + 1] = hudName

		hudDist = Drawing.new("Text")
		hudDist.Size = 12
		hudDist.Center = true
		hudDist.Outline = true
		hudDist.Color = Color3.fromRGB(255, 158, 208)
		hudDist.Visible = false
		S.drawings[#S.drawings + 1] = hudDist

		hudBarBg = Drawing.new("Square")
		hudBarBg.Filled = true
		hudBarBg.Color = Color3.fromRGB(30, 30, 40)
		hudBarBg.Visible = false
		S.drawings[#S.drawings + 1] = hudBarBg

		hudBarFill = Drawing.new("Square")
		hudBarFill.Filled = true
		hudBarFill.Color = Color3.fromRGB(255, 158, 208)
		hudBarFill.Visible = false
		S.drawings[#S.drawings + 1] = hudBarFill

		hudHpText = Drawing.new("Text")
		hudHpText.Size = 12
		hudHpText.Outline = true
		hudHpText.Color = Color3.fromRGB(220, 220, 230)
		hudHpText.Visible = false
		S.drawings[#S.drawings + 1] = hudHpText
	end)
	if not ok then
		warn("[Astolfo] Drawing API unavailable — no HUD.")
	end
end

local wmClock = 0

function S.setWmVisible(v)
	if wmPanel then
		wmPanel.Visible = v
	end
	for _, d in ipairs(wmLetters) do
		d.Visible = v
	end
end

-- chroma wave: pink -> lavender flows left to right across the letters
function S.stepWatermark(dt)
	dt = dt or 0
	wmClock = wmClock + dt
	for i, d in ipairs(wmLetters) do
		if d.Visible then
			local u = (wmClock * 0.35 - i * 0.13) % 1
			d.Color = Color3.fromRGB(255, 158, 208):Lerp(Color3.fromRGB(180, 155, 255), u)
		end
	end
end

local MODULE_HUD_ORDER = {
	{ name = "KillAura", get = function() return S.FEATURES.aura end },
	{ name = "AutoClicker", get = function() return S.FEATURES.autoclick end },
	{ name = "Velocity", get = function() return S.FEATURES.velocity end },
	{ name = "Speed", get = function() return S.FEATURES.speed end },
	{ name = "TargetStrafe", get = function() return S.FEATURES.strafe end },
	{ name = "Bhop", get = function() return S.FEATURES.bhop end },
	{ name = "NoSlow", get = function() return S.FEATURES.noslow end },
	{ name = "ESP", get = function() return S.FEATURES.esp end },
}

function S.updateModuleHud(dt)
	if not moduleTexts or #moduleTexts == 0 then
		return
	end
	local active = {}
	for _, e in ipairs(MODULE_HUD_ORDER) do
		if e.get() then
			active[#active + 1] = e.name
		end
	end
	-- black backdrop behind the watermark + list
	if wmPanel then
		local on = S.FEATURES.watermark or #active > 0
		wmPanel.Visible = on
		wmPanel.Size = Vector2.new(168, 30 + #active * 18)
		wmPanel.Position = Vector2.new(4, 4)
	end
	for i = 1, #moduleTexts do
		local d = moduleTexts[i]
		if i <= #active then
			d.Text = active[i]
			-- same chroma wave as the logo, flowing down the list
			local u = (wmClock * 0.35 - (i + 2) * 0.13) % 1
			d.Color = Color3.fromRGB(255, 158, 208):Lerp(Color3.fromRGB(180, 155, 255), u)
			d.Position = Vector2.new(10, 38 + (i - 1) * 18)
			d.Size = 14
			d.Visible = true
		else
			d.Visible = false
		end
	end
end

-- TargetHUD: name, smooth health bar with damage flash, distance
local hudHpShown = 20
local hudFlash = 0

function S.updateTargetHud(dt)
	local show = not S.killed and S.FEATURES.aura and S.target
	if not (hudPanel and hudName) then
		return
	end
	if not show then
		hudPanel.Visible = false
		hudName.Visible = false
		hudDist.Visible = false
		hudBarBg.Visible = false
		hudBarFill.Visible = false
		hudHpText.Visible = false
		return
	end
	local hp = S.targetAttr(S.target, "Health")
	if hp then
		if hp < hudHpShown - 0.01 then
			hudFlash = 0.3
		end
		hudHpShown = hudHpShown + (hp - hudHpShown) * math.min(1, dt * 8)
	else
		hudHpShown = 20
	end
	hudFlash = math.max(0, hudFlash - dt)
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	local px, py = 10, vp.Y - 110
	hudPanel.Size = Vector2.new(230, 84)
	hudPanel.Position = Vector2.new(px, py)
	hudPanel.Visible = true
	hudName.Position = Vector2.new(px + 14, py + 10)
	hudName.Text = S.target.Name
	hudName.Visible = true
	hudDist.Position = Vector2.new(px + 214, py + 14)
	hudDist.Text = math.floor(S.targetDist or 0) .. "m"
	hudDist.Visible = true
	hudBarBg.Size = Vector2.new(200, 10)
	hudBarBg.Position = Vector2.new(px + 14, py + 42)
	hudBarBg.Visible = true
	hudBarFill.Size = Vector2.new(math.max(0, 200 * math.clamp(hudHpShown / 20, 0, 1)), 10)
	hudBarFill.Position = Vector2.new(px + 14, py + 42)
	hudBarFill.Color = hudFlash > 0 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 158, 208)
	hudBarFill.Visible = true
	hudHpText.Position = Vector2.new(px + 14, py + 58)
	hudHpText.Text = string.format("%.1f / 20", hudHpShown)
	hudHpText.Visible = true
end
