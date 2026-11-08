-- MAME autoboot script for the Apollo DN3500 / DSP3500.
--
-- 1. Clock fix. At startup MAME loads the MC146818 RTC from host time, in
--    whatever BCD/binary mode the saved NVRAM has. Domain/OS keeps the RTC in
--    binary, 24-hour, UTC mode with a 2-digit year (96 = 1996). SR10.4 also
--    breaks after 2 Nov 1997. So on the first frame we rewrite the RTC in
--    Domain/OS's format with the host's UTC time shifted back
--    APOLLO_YEARS_BACK years (default 30).
--
-- 2. Tape swaps and pokes without the MAME UI. Write one line to
--    state/ctape.req:
--      <path>      load that cartridge tape image
--      unload      eject the tape
--      reset       soft reset;  hardreset: hard reset
--      dump        log the RTC registers
--      clock       re-apply the clock fix
--      lua <code>  run Lua
--    Results are appended to state/ctape.log.

local req = os.getenv("CTAPE_REQ") or "state/ctape.req"
local logf = os.getenv("CTAPE_LOG") or "state/ctape.log"
local years_back = tonumber(os.getenv("APOLLO_YEARS_BACK") or "30")
local RTC = 0x10900 -- DN3500/DSP3500 physical address of the MC146818

local function log(msg)
	local f = io.open(logf, "a")
	if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n"); f:close() end
end

local function space()
	return manager.machine.devices[":maincpu"].spaces["program"]
end

local function dump()
	local sp, t = space(), {}
	for i = 0, 13 do t[#t + 1] = string.format("%02x", sp:read_u8(RTC + i)) end
	return table.concat(t, " ")
end

local function set_clock()
	local sp = space()
	local u = os.date("!*t") -- host time, UTC
	local year = u.year - years_back
	sp:write_u8(RTC + 0x0b, 0x86) -- SET (halt updates) | binary | 24h
	sp:write_u8(RTC + 0x00, u.sec)
	sp:write_u8(RTC + 0x02, u.min)
	sp:write_u8(RTC + 0x04, u.hour)
	sp:write_u8(RTC + 0x06, u.wday) -- 1 = Sunday (weekday of the host date)
	sp:write_u8(RTC + 0x07, u.day)
	sp:write_u8(RTC + 0x08, u.month)
	sp:write_u8(RTC + 0x09, year % 100)
	sp:write_u8(RTC + 0x0b, 0x06) -- run: binary | 24h
	log(string.format("clock set to %04d-%02d-%02d %02d:%02d:%02d UTC (host minus %d years); rtc %s",
		year, u.month, u.day, u.hour, u.min, u.sec, years_back, dump()))
end

local function tape()
	for _, img in pairs(manager.machine.images) do
		if img.brief_instance_name == "ct" then return img end
	end
end

-- Keyboard injection for the DN3x00 (the Apollo keyboard has no natural-
-- keyboard support in MAME, so press the input fields directly).
local keymap
local function build_keymap()
	keymap = {}
	for tag, p in pairs(manager.machine.ioport.ports) do
		if tag:find(":kbd:keyboard") then
			for name, f in pairs(p.fields) do
				-- "\n" = main Return: works at the MD and bootshell prompts.
				-- "\r" = keypad Enter: what the Display Manager accepts (injected
				-- main Return is ignored there).
				if name == "Keyboard" then keymap["\n"] = { f = f }
				elseif name == "Numpad Enter" then keymap["\r"] = { f = f }
				elseif name == "Space" then keymap[" "] = { f = f }
				elseif name == "Shift" then keymap.shift = f
				elseif #name == 1 then keymap[name:lower()] = { f = f }
				elseif #name == 3 and name:sub(2, 2) == " " then  -- "1 !", "- _"
					keymap[name:sub(1, 1)] = { f = f }
					keymap[name:sub(3, 3)] = { f = f, shift = true }
				end
			end
		end
	end
end

local typing = {}       -- queue of {f, shift, n}
local function type_text(s)
	if not keymap then build_keymap() end
	for ch in s:gmatch(".") do
		local k = keymap[ch:lower()]
		if k then typing[#typing + 1] = { f = k.f, shift = k.shift, n = 14 }
		else log("type: no key for " .. ch) end
	end
end

-- 14 frames per key: shift down, key held ~8 frames, key up, shift up, gap.
-- Domain/OS (unlike the MD) drops presses only 2 frames long.
local function pump_typing()
	local k = typing[1]
	if not k then return end
	if k.shift and k.n == 14 then keymap.shift:set_value(1) end
	if k.n == 12 then k.f:set_value(1) end
	if k.n == 4 then k.f:clear_value() end
	if k.shift and k.n == 3 then keymap.shift:clear_value() end
	k.n = k.n - 1
	if k.n <= 0 then table.remove(typing, 1) end
end

-- Autoboot in Service mode (Normal-mode autoboot hangs in MAME 0.289: the
-- ROM spins polling the DUART at 0x10400 with a black screen). run.sh boot
-- sets APOLLO_AUTOBOOT=1;
-- type "ex domain_os" at the MD prompt and "go" at the bootshell ")" prompt.
local autoboot = os.getenv("APOLLO_AUTOBOOT") == "1"
local boot_steps = {
	{ at = 2,  text = "\n" },              -- first line after reset is swallowed
	{ at = 4,  text = "ex domain_os\n" },
	{ at = 90, text = "go\n" },            -- kernel + bootshell take ~30-75 s (emulated)
}

local clock_done = false

frame_sub = emu.add_machine_frame_notifier(function()
	if not clock_done then
		clock_done = true
		set_clock()
	end

	pump_typing()
	if autoboot and boot_steps[1] and manager.machine.time.seconds >= boot_steps[1].at then
		log("autoboot: typing " .. boot_steps[1].text:gsub("\n", "<CR>"))
		type_text(table.remove(boot_steps, 1).text)
	end

	local f = io.open(req, "r")
	if not f then return end
	local line = (f:read("*l") or ""):gsub("%s+$", "")
	f:close()
	os.remove(req)

	if line == "dump" then
		log("rtc " .. dump())
	elseif line:sub(1, 5) == "type " then
		type_text((line:sub(6):gsub("\\n", "\n"):gsub("\\r", "\r")))
		log("typing " .. line:sub(6))
	elseif line == "clock" then
		set_clock()
	elseif line:sub(1, 4) == "lua " then
		local fn, err = load(line:sub(5))
		if fn then
			local ok, res = pcall(fn)
			log("lua -> " .. tostring(ok) .. " " .. tostring(res))
		else
			log("lua compile error: " .. tostring(err))
		end
	elseif line == "reset" then
		manager.machine:soft_reset()
		log("soft reset")
	elseif line == "hardreset" then
		manager.machine:hard_reset()
		log("hard reset")
	else
		local img = tape()
		if not img then log("no ctape device"); return end
		img:unload()
		if line == "unload" or line == "" then
			log("tape unloaded")
		else
			local err = img:load(line)
			log("load " .. line .. " -> " .. tostring(err or "ok") .. " now=" .. tostring(img.filename))
		end
	end
end)

log("apollo.lua ready")
