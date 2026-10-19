-- esp — 2D boxes, health bars, tracers, target label, target glow
local S = getgenv().Astolfo

local label
local boxPool, tracerPool, hpBgPool, hpFgPool = {}, {}, {}, {}

do
	local ok = pcall(function()
		if not Drawing then
			error("no Drawing")
		end
		label = Drawing.new("Text")
		label.Size = 16
		label.Center = true
		label.Outline = true
		label.Color = Color3.fromRGB(255, 255, 255)
		label.Visible = false
		S.drawings[#S.drawings + 1] = label

		for _ = 1, 24 do
			local sq = Drawing.new("Square")
			sq.Thickness = 2
			sq.Filled = false
			sq.Color = Color3.fromRGB(255, 60, 60)
			sq.Visible = false
			S.drawings[#S.drawings + 1] = sq
			boxPool[#boxPool + 1] = sq

			local tr = Drawing.new("Line")
			tr.Thickness = 1
			tr.Color = Color3.fromRGB(255, 90, 90)
			tr.Transparency = 0.45
			tr.Visible = false
			S.drawings[#S.drawings + 1] = tr
			tracerPool[#tracerPool + 1] = tr

			local hbg = Drawing.new("Square")
			hbg.Filled = true
			hbg.Color = Color3.fromRGB(10, 10, 10)
			hbg.Transparency = 0.4
			hbg.Visible = false
			S.drawings[#S.drawings + 1] = hbg
			hpBgPool[#hpBgPool + 1] = hbg

			local hfg = Drawing.new("Square")
			hfg.Filled = true
			hfg.Color = Color3.fromRGB(80, 255, 100)
			hfg.Visible = false
			S.drawings[#S.drawings + 1] = hfg
			hpFgPool[#hpFgPool + 1] = hfg
		end
	end)
	if not ok then
		warn("[Astolfo] Drawing API unavailable — no ESP.")
	end
end

-- bright glow around the KillAura target (visible through walls)
S.glow = nil
function S.stepGlow()
	local show = not S.killed and S.FEATURES.aura and S.FEATURES.glow and S.target
	if show then
		if not S.glow then
			S.glow = Instance.new("Highlight")
			S.glow.Name = "AstolfoTarget"
			S.glow.FillColor = Color3.fromRGB(255, 45, 45)
			S.glow.FillTransparency = 0.55
			S.glow.OutlineColor = Color3.fromRGB(255, 70, 70)
			S.glow.OutlineTransparency = 0
			S.glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		end
		if S.glow.Parent ~= S.target then
			S.glow.Parent = S.target
		end
	elseif S.glow then
		S.glow.Parent = nil
	end
end

function S.stepEsp(dt)
	local camera = S.Workspace.CurrentCamera
	if not camera then
		return
	end
	local screenPos
	if S.targetPos then
		local p, onScreen = camera:WorldToViewportPoint(S.targetPos)
		screenPos = onScreen and p or nil
	end
	if not S.FEATURES.esp then
		if boxPool[1] then
			for i = 1, #boxPool do
				boxPool[i].Visible = false
				tracerPool[i].Visible = false
				hpBgPool[i].Visible = false
				hpFgPool[i].Visible = false
			end
		end
		if label then
			label.Visible = false
		end
		return
	end

	local myPos = S.selfPos()
	local cands = S.targetCandidates()
	local vp = camera.ViewportSize
	for i = 1, #boxPool do
		local m = cands[i]
		local sq, tr, hbg, hfg = boxPool[i], tracerPool[i], hpBgPool[i], hpFgPool[i]
		if m then
			local h = S.findHead(m)
			if h and h.Parent then
				local p, onScreen = camera:WorldToViewportPoint(h.Position)
				if onScreen then
					local d = (h.Position - myPos).Magnitude
					local size = math.clamp(900 / math.max(d, 1), 18, 180)
					sq.Size = Vector2.new(size, size * 1.35)
					sq.Position = Vector2.new(p.X - size / 2, p.Y - size * 0.68)
					sq.Thickness = m == S.target and 3 or 2
					sq.Color = m == S.target and Color3.fromRGB(255, 255, 120) or Color3.fromRGB(255, 60, 60)
					sq.Visible = true
					tr.From = Vector2.new(p.X, p.Y)
					tr.To = Vector2.new(vp.X / 2, vp.Y)
					tr.Visible = true
					local hp = S.targetHealth(m)
					if hp then
						local frac = math.clamp(hp / 20, 0, 1)
						hbg.Position = Vector2.new(p.X - size / 2, p.Y - size * 0.68 - 7)
						hbg.Size = Vector2.new(size, 5)
						hbg.Visible = true
						hfg.Position = hbg.Position
						hfg.Size = Vector2.new(size * frac, 5)
						hfg.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 90), frac)
						hfg.Visible = true
					else
						hbg.Visible = false
						hfg.Visible = false
					end
				else
					sq.Visible, tr.Visible, hbg.Visible, hfg.Visible = false, false, false, false
				end
			else
				sq.Visible, tr.Visible, hbg.Visible, hfg.Visible = false, false, false, false
			end
		else
			sq.Visible, tr.Visible, hbg.Visible, hfg.Visible = false, false, false, false
		end
	end
	if label then
		if screenPos and S.target then
			local hp = S.targetHealth(S.target)
			label.Position = Vector2.new(screenPos.X, screenPos.Y - 60)
			label.Text = S.target.Name .. " [" .. math.floor(S.targetDist or 0) .. "]"
				.. (hp and ("  " .. math.floor(hp) .. "hp") or "")
			label.Visible = true
		else
			label.Visible = false
		end
	end
end
