-- ProbeState — find the LIVE local player state table.
--   * player attributes (the sim mirrors state into attributes: Tick/Rsp/Rsy/...)
--   * MCInputs context action states
--   * upvalues of the Client + Simulation script closures, hunting for the
--     state table (has .box and .yaw) — that's the object to set speedLevel on
-- Run: loadstring(game:HttpGet("<raw url>"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

print("[state] === player attributes ===")
local attrs = player:GetAttributes()
local n = 0
for k, v in pairs(attrs) do
	n = n + 1
	if n <= 25 then
		print(string.format("  %s = %s", tostring(k), tostring(v):sub(1, 60)))
	end
end
print("[state] (" .. n .. " attributes total)")

print("[state] === MCInputs context ===")
local ctx = player:FindFirstChild("MCInputs")
if ctx then
	for _, a in ipairs(ctx:GetChildren()) do
		if a:IsA("InputAction") then
			local ok, st = pcall(function()
				return a:GetState()
			end)
			print("  " .. a.Name .. " state=" .. tostring(ok and tostring(st) or "?err"))
		end
	end
else
	print("  no MCInputs context")
end

--------------------------------------------------------------------
-- closure upvalue scan
--------------------------------------------------------------------

local gsc = rawget((getgenv and getgenv()) or _G, "getscriptclosure")
local guv = rawget((getgenv and getgenv()) or _G, "getupvalues")

local function describeState(label, where, st)
	print(string.format("[state] %s: x=%.2f y=%.2f z=%.2f yaw=%.2f pitch=%s sprinting=%s sneaking=%s speedLevel=%s slownessLevel=%s abilitySpeed=%s onGround=%s health=%s",
		where, st.x or 0, st.y or 0, st.z or 0, st.yaw or 0, tostring(st.pitch), tostring(st.sprinting),
		tostring(st.sneaking), tostring(st.speedLevel), tostring(st.slownessLevel), tostring(st.abilitySpeed),
		tostring(st.onGround), tostring(st.vitals and st.vitals.health or st.health or "?")))
end

local function scanClosure(label, script)
	if not (gsc and guv) then
		print("[state] no closure tools (getscriptclosure/getupvalues)")
		return
	end
	local ok, cl = pcall(gsc, script)
	if not ok then
		print("[state] " .. label .. ": getscriptclosure failed: " .. tostring(cl))
		return
	end
	local ok2, ups = pcall(guv, cl)
	if not ok2 then
		print("[state] " .. label .. ": getupvalues failed")
		return
	end
	print("[state] === " .. label .. " upvalues: " .. #ups .. " ===")
	for i, u in ipairs(ups) do
		local t = typeof(u)
		if t == "table" then
			if type(u.box) == "table" and type(u.yaw) == "number" then
				describeState(label, "#" .. i .. " IS state", u)
			end
			local found = {}
			for k, v in pairs(u) do
				if typeof(v) == "table" and type(v.box) == "table" and type(v.yaw) == "number" then
					found[#found + 1] = k
				end
			end
			if #found > 0 then
				for _, k in ipairs(found) do
					describeState(label, "#" .. i .. "." .. tostring(k), u[k])
				end
			end
			local keys = {}
			for k in pairs(u) do
				keys[#keys + 1] = tostring(k)
			end
			table.sort(keys)
			local shown = {}
			for j = 1, math.min(#keys, 16) do
				shown[j] = keys[j]
			end
			if #found == 0 and not (type(u.box) == "table" and type(u.yaw) == "number") then
				print(string.format("  #%d table {%s}%s", i, table.concat(shown, ","), #keys > 16 and (" +" .. #keys - 16) or ""))
			end
		elseif t == "function" then
			print(string.format("  #%d function", i))
		else
			print(string.format("  #%d %s = %s", i, t, tostring(u):sub(1, 40)))
		end
	end
end

scanClosure("Client", player:WaitForChild("PlayerScripts", 8):FindFirstChild("Client"))
scanClosure("Simulation", ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Simulation"))

print("[state] done")
