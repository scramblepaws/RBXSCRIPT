-- DumpSrc — real source via the executor's native decompiler (the [C] one).
-- Prints each module's source with a header and a cap. Paste the output back
-- (in several messages if the console chops it); I'll request focused reruns
-- for anything truncated.
-- Run: loadstring(game:HttpGet("<raw url>"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local dec = rawget((getgenv and getgenv()) or _G, "decompile")
if type(dec) ~= "function" then
	print("[dump] no decompile global — run in a fresh session (before any external decompiler loads)")
	return
end
local okSrc, srcInfo = pcall(debug.info, dec, "s")
print("[dump] decompile source: " .. tostring(okSrc and srcInfo))

local function resolve(path)
	local node
	if path:sub(1, 12) == "PlayerScr" then
		node = player and player:FindFirstChild("PlayerScripts")
		path = path:sub(14)
	else
		node = ReplicatedStorage
	end
	for part in path:gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local JOBS = {
	{ "PlayerScripts/Client", 12000 },
	{ "Shared/MCPhysics/Combat", 6000 },
	{ "Shared/MCPhysics/Movement", 6000 },
	{ "Shared/MCPhysics/Constants", 4000 },
	{ "Shared/MCPhysics/Collision", 4000 },
	{ "Shared/Net/Inputs", 6000 },
	{ "Shared/Net/MoveAuthority", 5000 },
	{ "Shared/Net/Simulation", 6000 },
	{ "Shared/AimAssist", 3000 },
	{ "Shared/LagComp", 3000 },
	{ "Shared/SnapshotBuffer", 3000 },
}

for _, job in ipairs(JOBS) do
	local inst = resolve(job[1])
	if not inst then
		print("==== " .. job[1] .. " ====\n  NOT FOUND")
	else
		local ok, src = pcall(dec, inst)
		if ok and type(src) == "string" then
			print("==== " .. job[1] .. " (" .. #src .. " chars) ====")
			print(src:sub(1, job[2]))
			if #src > job[2] then
				print("... TRUNCATED at " .. job[2] .. "/" .. #src .. " chars — ask for a focused rerun")
			end
		else
			print("==== " .. job[1] .. " ====\n  decompile failed: " .. tostring(src))
		end
	end
end

-- Client's children (the controller is likely split into sub-modules)
local client = resolve("PlayerScripts/Client")
if client then
	local names = {}
	for _, c in ipairs(client:GetChildren()) do
		names[#names + 1] = c.Name .. "(" .. c.ClassName .. ")"
	end
	print("[dump] Client children: " .. (next(names) and table.concat(names, ", ") or "none"))
	for _, c in ipairs(client:GetChildren()) do
		if c:IsA("ModuleScript") or c:IsA("LocalScript") then
			local ok, src = pcall(dec, c)
			if ok and type(src) == "string" then
				print("==== PlayerScripts/Client/" .. c.Name .. " (" .. #src .. " chars) ====")
				print(src:sub(1, 5000))
				if #src > 5000 then
					print("... TRUNCATED")
				end
			end
		end
	end
end

print("[dump] done")
