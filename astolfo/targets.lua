-- targets — who the aura can lock onto
local S = getgenv().Astolfo
local Workspace = S.Workspace
local player = S.player

local function isTargetBody(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("Model") then
		return false
	end
	local name = inst.Name
	if name == "MCBody" or name == "MCBody " .. tostring(player.UserId) or name:sub(1, 6) ~= "MCBody" then
		return false
	end
	if S.VALUES.targets == "Players" and name:find("Bot") then
		return false
	end
	if S.VALUES.targets == "Bots" and not name:find("Bot") then
		return false
	end
	return true
end

function S.targetCandidates()
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

function S.findTarget()
	local myPos = S.selfPos()
	local best, bestDist, bestPos
	for _, m in ipairs(S.targetCandidates()) do
		local h = S.findHead(m)
		if h and h.Parent then
			local d = (h.Position - myPos).Magnitude
			if d <= S.VALUES.range and d < (bestDist or math.huge) then
				best, bestDist, bestPos = m, d, h.Position
			end
		end
	end
	return best, bestDist, bestPos
end
