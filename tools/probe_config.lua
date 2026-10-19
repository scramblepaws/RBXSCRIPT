-- ProbeConfig — dump the game's config/constant tables with real values (numbers, strings),
-- and expand the table-valued upvalues of the movement/combat functions. This is where
-- walk speed / gravity / reach limits live; no decompiling needed.
-- Run: loadstring(game:HttpGet("<raw url>"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MODULES = {
	"Shared/Config",
	"Shared/MCPhysics",
	"Shared/Net/MoveAuthority",
	"Shared/AimAssist",
	"Shared/Net/Inputs",
	"Shared/LagComp",
}

local UP_FUNCS = {
	{ "Shared/MCPhysics", { "Collision.move", "Collision.step", "Combat.clientAttack", "Combat.boxDistance" } },
	{ "Shared/Net/MoveAuthority", { "judge", "capture", "apply", "read", "newWatch", "newBook" } },
}

local MAX_PER_TABLE = 30
local MAX_DEPTH = 3

local function shortVal(v, depth, seen)
	local t = typeof(v)
	if t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:sub(1, 40) .. '"'
	elseif t == "function" then
		return "function"
	elseif t == "table" then
		if depth >= MAX_DEPTH then
			return "{...}"
		end
		if seen[v] then
			return "<cycle>"
		end
		seen[v] = true
		local parts, n = {}, 0
		for k, val in pairs(v) do
			n = n + 1
			if n > MAX_PER_TABLE then
				parts[#parts + 1] = "..."
				break
			end
			parts[#parts + 1] = tostring(k) .. "=" .. shortVal(val, depth + 1, seen)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v):sub(1, 40)
end

local function findLive(path)
	local node = ReplicatedStorage
	for part in path:gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local function dumpModule(path)
	local inst = findLive(path)
	print("==== " .. path .. " ====")
	if not inst then
		print("  not found")
		return nil
	end
	local ok, mod = pcall(require, inst)
	if not ok or typeof(mod) ~= "table" then
		print("  require failed: " .. tostring(mod))
		return nil
	end
	local keys = {}
	for k in pairs(mod) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, k in ipairs(keys) do
		local v = mod[k]
		if typeof(v) ~= "function" then
			print(string.format("  %s = %s", tostring(k), shortVal(v, 0, {})))
		else
			print(string.format("  %s = function", tostring(k)))
		end
	end
	return mod
end

local loaded = {}
for _, path in ipairs(MODULES) do
	loaded[path] = dumpModule(path)
end

--------------------------------------------------------------------
-- Upvalues of the movement/combat functions (tables expanded)
--------------------------------------------------------------------

local getupvalues = rawget((getgenv and getgenv()) or _G, "getupvalues")
if type(getupvalues) == "function" then
	for _, entry in ipairs(UP_FUNCS) do
		local mod = loaded[entry[1]]
		if mod then
			for _, fnPath in ipairs(entry[2]) do
				local node = mod
				for part in fnPath:gmatch("[^%.]+") do
					node = node and node[part]
				end
				if type(node) == "function" then
					local ok, ups = pcall(getupvalues, node)
					if ok and type(ups) == "table" then
						local parts = {}
						for i, u in ipairs(ups) do
							if i > 12 then
								parts[#parts + 1] = "..."
								break
							end
							parts[#parts + 1] = "#" .. i .. "=" .. shortVal(u, 0, {})
						end
						print(string.format("  %s.%s upvalues: %s", entry[1]:gsub("Shared/", ""), fnPath,
							table.concat(parts, ", ")))
					end
				end
			end
		end
	end
else
	print("[probe] no getupvalues")
end

print("[probe] done")
