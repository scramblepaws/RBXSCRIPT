-- Introspect — read the game's own shared modules at runtime instead of decompiling.
-- Prints: executor capabilities, module table structure (constants!), and closure upvalues
-- (where things like walk speed live). Also tries a native decompiler and the Konstant API.
-- Run: loadstring(game:HttpGet("<raw url>"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MAX_LINES_PER_MODULE = 70
local MAX_DECOMPILE_CHARS = 1200

local MODULES = {
	"Shared/MCPhysics",
	"Shared/Net/Inputs",
	"Shared/Net/MoveAuthority",
	"Shared/LagComp",
	"Shared/AimAssist",
	"Shared/Net/Simulation",
	"Shared/SnapshotBuffer",
}

--------------------------------------------------------------------
-- Capabilities
--------------------------------------------------------------------

local names = {
	"decompile", "getscriptbytecode", "getscriptclosure", "request", "http_request", "syn",
	"hookfunction", "replaceclosure", "clonefunction", "hookmetamethod", "getupvalues",
	"getupvalue", "setupvalue", "getconstants", "getprotos",
}
local caps = {}
for _, n in ipairs(names) do
	local v = rawget((getgenv and getgenv()) or _G, n)
	caps[#caps + 1] = n .. "=" .. tostring(v ~= nil)
end
print("[introspect] caps: " .. table.concat(caps, " "))

local decompileFn = rawget((getgenv and getgenv()) or _G, "decompile")
print("[introspect] native decompile: " .. tostring(type(decompileFn) == "function"))

--------------------------------------------------------------------
-- Module table + upvalue dump
--------------------------------------------------------------------

local function shortVal(v)
	local t = typeof(v)
	if t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:sub(1, 32) .. '"'
	elseif t == "function" then
		return "function"
	elseif t == "table" then
		return "table"
	end
	return tostring(v):sub(1, 32)
end

local out = {}
local function line(s)
	if #out < MAX_LINES_PER_MODULE then
		out[#out + 1] = s
	end
end

local getupvalues = rawget((getgenv and getgenv()) or _G, "getupvalues")
local debug_getupvalue = debug and debug.getupvalue

local function dumpUpvalues(fn, label)
	local ups
	if type(getupvalues) == "function" then
		local ok, res = pcall(getupvalues, fn)
		if ok then
			ups = res
		end
	elseif type(debug_getupvalue) == "function" then
		ups = {}
		for i = 1, 30 do
			local ok, name, val = pcall(debug_getupvalue, fn, i)
			if not ok or name == nil then
				break
			end
			ups[i] = { name, val }
		end
	end
	if not ups then
		return
	end
	for i, entry in ipairs(ups) do
		if type(entry) == "table" then
			line(string.format("    up %s: %s | %s = %s", label, tostring(entry[1]), tostring(entry[2]),
				shortVal(entry[3] ~= nil and entry[3] or entry[1])))
		elseif typeof(entry) ~= "nil" then
			line(string.format("    up %s #%d = %s", label, i, shortVal(entry)))
		end
		if i > 12 then
			break
		end
	end
end

local function dumpTable(t, prefix, depth)
	if depth > 2 or typeof(t) ~= "table" then
		return
	end
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, k in ipairs(keys) do
		local v = t[k]
		local tv = typeof(v)
		line(string.format("  %s%s = %s", prefix, tostring(k), shortVal(v)))
		if tv == "table" then
			dumpTable(v, prefix .. tostring(k) .. ".", depth + 1)
		elseif tv == "function" then
			dumpUpvalues(v, tostring(k))
		end
	end
end

--------------------------------------------------------------------
-- Run
--------------------------------------------------------------------

for _, modPath in ipairs(MODULES) do
	out = {}
	line("==== " .. modPath .. " ====")

	local inst = ReplicatedStorage
	for part in modPath:gmatch("[^/]+") do
		inst = inst and inst:FindFirstChild(part)
	end

	if not inst then
		line("  instance not found")
	else
		local ok, mod = pcall(require, inst)
		if not ok then
			line("  require failed: " .. tostring(mod))
		elseif typeof(mod) == "table" then
			dumpTable(mod, "", 1)
		else
			line("  returned " .. typeof(mod) .. ": " .. shortVal(mod))
		end
	end

	print(table.concat(out, "\n"))

	if #out >= MAX_LINES_PER_MODULE then
		print("  ... [truncated]")
	end
end

--------------------------------------------------------------------
-- Konstant API fallback (server-side decompiler)
--------------------------------------------------------------------

local requestFn = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
if type(requestFn) == "function" and type(getscriptbytecode) == "function" then
	for _, modPath in ipairs({ "Shared/MCPhysics", "Shared/Net/Inputs" }) do
		local inst = ReplicatedStorage
		for part in modPath:gmatch("[^/]+") do
			inst = inst and inst:FindFirstChild(part)
		end
		if inst then
			local okBc, bc = pcall(getscriptbytecode, inst)
			if okBc and type(bc) == "string" then
				task.wait(0.6)
				local okReq, res = pcall(requestFn, {
					Url = "http://api.plusgiant5.com/konstant/decompile",
					Method = "POST",
					Body = bc,
					Headers = { ["Content-Type"] = "text/plain" },
				})
				print("==== konstant: " .. modPath .. " ====")
				if okReq and res and res.StatusCode == 200 then
					print(tostring(res.Body):sub(1, MAX_DECOMPILE_CHARS))
				else
					print("konstant failed: " .. tostring(okReq and res and res.StatusCode or res))
				end
			end
		end
	end
else
	print("[introspect] no request function — skipping konstant api")
end

print("[introspect] done")
