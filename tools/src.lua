-- Src — print the game's real source using the EXECUTOR's native decompile (not the external one,
-- which rejects this bytecode version). Ordered by usefulness.
-- Run: loadstring(game:HttpGet("<raw url>"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JOBS = {
	{ path = "Shared/MCPhysics", cap = 9000 }, -- Combat.clientAttack, REACH, MAX_HEALTH
	{ path = "Shared/Net/Inputs", cap = 9000 }, -- fireAttack / input packet
	{ path = "Shared/Net/MoveAuthority", cap = 7000 }, -- movement schema + judge (anti-cheat)
	{ path = "Shared/AimAssist", cap = 4000 },
	{ path = "Shared/LagComp", cap = 4000 },
	{ path = "Shared/SnapshotBuffer", cap = 3000 },
	{ path = "Shared/Net/Simulation", cap = 3000 }, -- 103KB bytecode: head only
}

local decompileFn = rawget((getgenv and getgenv()) or _G, "decompile")
if type(decompileFn) ~= "function" then
	print("[src] no native decompile available")
	return
end

local function findLive(path)
	local node = ReplicatedStorage
	for part in path:gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

for _, job in ipairs(JOBS) do
	local inst = findLive(job.path)
	print("==== " .. job.path .. " ====")
	if not inst then
		print("  not found")
	else
		-- executors differ: some take the instance, some the bytecode, so try both
		local src
		local ok, res = pcall(decompileFn, inst)
		if ok and type(res) == "string" and #res > 0 then
			src = res
		else
			local okBc, bc = pcall(getscriptbytecode, inst)
			if okBc and type(bc) == "string" then
				local ok2, res2 = pcall(decompileFn, bc)
				if ok2 and type(res2) == "string" and #res2 > 0 then
					src = res2
				end
			end
		end
		if src then
			print(string.format("-- %d chars", #src))
			print(src:sub(1, job.cap))
			if #src > job.cap then
				print("-- ... [truncated at " .. job.cap .. " of " .. #src .. "]")
			end
		else
			print("  decompile failed: " .. tostring(ok and res or res))
		end
	end
end

print("[src] done")
