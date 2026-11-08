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

-- Civil date <-> days since 1970-01-01 (proleptic Gregorian, UTC).
local function days_from_civil(y, m, d)
	y = (m <= 2) and (y - 1) or y
	local era = (y >= 0 and y or y - 399) // 400
	local yoe = y - era * 400
	local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

local function civil_from_days(z)
	z = z + 719468
	local era = (z >= 0 and z or z - 146096) // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local d = doy - (153 * mp + 2) // 5 + 1
	local m = mp + (mp < 10 and 3 or -9)
	return (m <= 2) and (y + 1) or y, m, d
end

local function epoch(y, mo, d, h, mi, s)
	return days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s
end

-- The Apollo's own time as last seen (state/apollo-clock). Under -nothrottle
-- emulated time runs faster than real time, so Domain/OS can shut down with
-- a time ahead of "host minus N years"; setting the RTC behind that makes the
-- kernel stop with "The calendar is more than a minute slow".
local clockf = os.getenv("APOLLO_CLOCK_FILE") or "state/apollo-clock"

local function read_rtc_epoch()
	local sp = space()
	local b = sp:read_u8(RTC + 0x0b)
	if (b & 0x04) == 0 or sp:read_u8(RTC + 0x0a) & 0x70 ~= 0x20 then return nil end -- not binary / not running
	local yy = sp:read_u8(RTC + 0x09)
	local year = (yy >= 70) and (1900 + yy) or (2000 + yy)
	local mo, d = sp:read_u8(RTC + 0x08), sp:read_u8(RTC + 0x07)
	if mo < 1 or mo > 12 or d < 1 or d > 31 then return nil end
	return epoch(year, mo, d, sp:read_u8(RTC + 0x04), sp:read_u8(RTC + 0x02), sp:read_u8(RTC + 0x00))
end

local function save_clock()
	local e = read_rtc_epoch()
	if not e then return end
	local f = io.open(clockf, "w")
	if f then f:write(tostring(e) .. "\n"); f:close() end
end

local function set_clock()
	local sp = space()
	local u = os.date("!*t") -- host time, UTC
	local target = epoch(u.year - years_back, u.month, u.day, u.hour, u.min, u.sec)
	local why = string.format("host minus %d years", years_back)
	local f = io.open(clockf, "r")
	if f then
		local saved = tonumber(f:read("*l") or "")
		f:close()
		if saved and saved + 60 > target then
			target = saved + 60
			why = "last Apollo time + 60 s"
		end
	end
	local days = target // 86400
	local secs = target % 86400
	local y, mo, d = civil_from_days(days)
	local h, mi, s = secs // 3600, (secs % 3600) // 60, secs % 60
	sp:write_u8(RTC + 0x0b, 0x86) -- SET (halt updates) | binary | 24h
	sp:write_u8(RTC + 0x00, s)
	sp:write_u8(RTC + 0x02, mi)
	sp:write_u8(RTC + 0x04, h)
	sp:write_u8(RTC + 0x06, (days + 4) % 7 + 1) -- 1 = Sunday
	sp:write_u8(RTC + 0x07, d)
	sp:write_u8(RTC + 0x08, mo)
	sp:write_u8(RTC + 0x09, y % 100)
	sp:write_u8(RTC + 0x0a, 0x20) -- divider on (32.768 kHz); 0x00 = clock stopped
	sp:write_u8(RTC + 0x0b, 0x06) -- run: binary | 24h
	log(string.format("clock set to %04d-%02d-%02d %02d:%02d:%02d UTC (%s); rtc %s",
		y, mo, d, h, mi, s, why, dump()))
	save_clock()
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
frames = 0

stop_sub = emu.add_machine_stop_notifier(save_clock)

frame_sub = emu.add_machine_frame_notifier(function()
	if not clock_done then
		clock_done = true
		set_clock()
	end

	frames = frames + 1
	if frames % 120 == 0 then save_clock() end -- survives kill -9 too

	pump_typing()
	if autoboot and boot_steps[1] and manager.machine.time.seconds >= boot_steps[1].at then
		log("autoboot: typing " .. boot_steps[1].text:gsub("\n", "<CR>"))
		type_text(table.remove(boot_steps, 1).text)
	end

	local f = io.open(req, "r")
	if not f then return end
	local line = (f:read("*l") or ""):gsub("%s+$", "")
	f:close()
	if line == "" then return end -- caught mid-write; read it again next frame
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
		if line == "unload" then
			log("tape unloaded")
		else
			local err = img:load(line)
			log("load " .. line .. " -> " .. tostring(err or "ok") .. " now=" .. tostring(img.filename))
		end
	end
end)

log("apollo.lua ready")
