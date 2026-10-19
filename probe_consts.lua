-- ProbeConsts — inspect the game's functions without decompiling:
--   * tells native (C) decompile apart from the url-loaded one
--   * prints constants/strings and upvalue values for the key attack/movement functions
--   * tries the Konstant API as a last-resort decompiler
-- Run: loadstring(game:HttpGet("<raw url>"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------
-- Is the current `decompile` the executor's, or the url-loaded one?
--------------------------------------------------------------------

local dec = rawget((getgenv and getgenv()) or _G, "decompile")
if type(dec) == "function" then
	local ok, src = pcall(debug.info, dec, "s")
	print(string.format("[probe] decompile: source=%s (native if [C])", tostring(ok and src or "?")))
	if tostring(src) == "[C]" then
		print("[probe] NATIVE decompile detected — trying it on MCPhysics")
		local node = ReplicatedStorage
		for part in ("Shared/MCPhysics"):gmatch("[^/]+") do
			node = node and node:FindFirstChild(part)
		end
		local ok2, res = pcall(dec, node)
		if ok2 and type(res) == "string" then
			print("---- native decompile: Shared/MCPhysics (" .. #res .. " chars) ----")
			print(res:sub(1, 6000))
		else
			print("[probe] native decompile failed: " .. tostring(res))
		end
	end
else
	print("[probe] decompile: none")
end

--------------------------------------------------------------------
-- Function internals
--------------------------------------------------------------------

local getconstants = rawget((getgenv and getgenv()) or _G, "getconstants")
local getprotos = rawget((getgenv and getgenv()) or _G, "getprotos")
local getupvalues = rawget((getgenv and getgenv()) or _G, "getupvalues")

local function findLive(path)
	local node = ReplicatedStorage
	for part in path:gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local function shortVal(v)
	local t = typeof(v)
	if t == "string" then
		return '"' .. v:sub(1, 40) .. '"'
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		return "{table " .. tostring(#v) .. "}"
	end
	return tostring(v):sub(1, 40)
end

local function describeFunction(label, fn)
	if type(fn) ~= "function" then
		print("  " .. label .. ": not a function")
		return
	end
	local okA, arity = pcall(debug.info, fn, "a")
	print(string.format("  %s: arity=%s", label, tostring(okA and arity or "?")))

	if type(getprotos) == "function" then
		local ok, protos = pcall(getprotos, fn)
		if ok and type(protos) == "table" then
			print(string.format("    protos: %d", #protos))
		end
	end
	if type(getconstants) == "function" then
		local ok, consts = pcall(getconstants, fn)
		if ok and type(consts) == "table" then
			local parts, n = {}, 0
			for _, c in ipairs(consts) do
				local t = typeof(c)
				if t == "string" or t == "number" then
					n = n + 1
					if n > 24 then
						parts[#parts + 1] = "..."
						break
					end
					parts[#parts + 1] = shortVal(c)
				end
			end
			print("    consts: " .. table.concat(parts, ", "))
		end
	end
	if type(getupvalues) == "function" then
		local ok, ups = pcall(getupvalues, fn)
		if ok and type(ups) == "table" then
			local parts = {}
			for i, u in ipairs(ups) do
				if i > 10 then
					parts[#parts + 1] = "..."
					break
				end
				local t = typeof(u)
				if t == "table" and u.name ~= nil then -- {name, value} style
					parts[#parts + 1] = tostring(u.name) .. "=" .. shortVal(u.value)
				else
					parts[#parts + 1] = "#" .. i .. "=" .. shortVal(u)
				end
			end
			print("    upvalues: " .. table.concat(parts, ", "))
		end
	end
end

local TARGETS = {
	{ "Shared/MCPhysics", "Combat.clientAttack" },
	{ "Shared/MCPhysics", "Combat.boxDistance" },
	{ "Shared/Net/Inputs", "fireAttack" },
	{ "Shared/Net/Inputs", "readAttack" },
	{ "Shared/Net/Inputs", "fireLook" },
	{ "Shared/Net/MoveAuthority", "judge" },
	{ "Shared/Net/MoveAuthority", "capture" },
	{ "Shared/Net/MoveAuthority", "apply" },
	{ "Shared/Net/MoveAuthority", "read" },
	{ "Shared/AimAssist", "anglesTo" },
	{ "Shared/AimAssist", "pull" },
}

for _, t in ipairs(TARGETS) do
	local inst = findLive(t[1])
	local ok, mod = pcall(require, inst)
	if not ok or typeof(mod) ~= "table" then
		print("  " .. t[1] .. "." .. t[2] .. ": module unavailable")
	else
		local fn, node = mod, nil
		for part in t[2]:gmatch("[^%.]+") do
			node = node and node[part] or fn[part]
		end
		describeFunction(t[1]:gsub("Shared/", "") .. "." .. t[2], node)
	end
end

--------------------------------------------------------------------
-- Konstant API (server-side decompiler)
--------------------------------------------------------------------

local requestFn = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
if type(requestFn) == "function" and type(getscriptbytecode) == "function" then
	local node = ReplicatedStorage
	for part in ("Shared/MCPhysics"):gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	local okBc, bc = pcall(getscriptbytecode, node)
	if okBc and type(bc) == "string" then
		local okReq, res = pcall(requestFn, {
			Url = "http://api.plusgiant5.com/konstant/decompile",
			Method = "POST",
			Body = bc,
			Headers = { ["Content-Type"] = "text/plain" },
		})
		print("==== konstant api ====")
		if okReq and res and res.StatusCode == 200 then
			print(tostring(res.Body):sub(1, 3000))
		else
			print("failed: " .. tostring(okReq and res and res.StatusCode or res))
		end
	end
else
	print("[probe] no request fn — konstant skipped")
end

print("[probe] done")
