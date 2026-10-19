-- DumpSrc2 — focused second pass: full Inputs, the Client controller (with debug),
-- and the small modules that define the state and damage APIs.
-- Run: loadstring(game:HttpGet("<raw url>"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local dec = rawget((getgenv and getgenv()) or _G, "decompile")
if type(dec) ~= "function" then
	print("[dump2] no decompile global")
	return
end

local function dump(label, inst, cap)
	if not inst then
		print("==== " .. label .. " ====\n  NOT FOUND")
		return
	end
	local ok, src = pcall(dec, inst)
	if ok and type(src) == "string" then
		print("==== " .. label .. " (" .. #src .. " chars) ====")
		print(src:sub(1, cap))
		if #src > cap then
			print("... TRUNCATED at " .. cap .. "/" .. #src .. " — ask for a focused rerun")
		end
	else
		print("==== " .. label .. " ====\n  decompile failed: " .. tostring(src))
	end
end

-- Client controller, with debug so we can see why it was missing before
local ps = player:WaitForChild("PlayerScripts", 8)
print("[dump2] PlayerScripts children: ")
for _, c in ipairs(ps:GetChildren()) do
	print("[dump2]   " .. c.Name .. "(" .. c.ClassName .. ")")
end

dump("PlayerScripts/Client", ps:FindFirstChild("Client"), 16000)

-- Client sub-modules
local client = ps:FindFirstChild("Client")
if client then
	for _, c in ipairs(client:GetChildren()) do
		if c:IsA("ModuleScript") or c:IsA("LocalScript") then
			dump("PlayerScripts/Client/" .. c.Name, c, 6000)
		end
	end
end

local function rsPart(path)
	local node = ReplicatedStorage
	for part in path:gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

dump("Shared/Net/Inputs", rsPart("Shared/Net/Inputs"), 11000)
dump("Shared/MCPhysics/Types", rsPart("Shared/MCPhysics/Types"), 6000)
dump("Shared/MCPhysics/Damage", rsPart("Shared/MCPhysics/Damage"), 8000)
dump("Shared/MCPhysics/Knockback", rsPart("Shared/MCPhysics/Knockback"), 4000)
dump("Shared/MCPhysics/Blocks", rsPart("Shared/MCPhysics/Blocks"), 9000)

print("[dump2] done")
