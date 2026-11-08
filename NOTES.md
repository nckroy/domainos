# Field notes: installing Domain/OS SR10.4 under MAME

Things that weren't obvious, found the hard way while doing the install on
macOS (Apple silicon, MAME 0.289 from Homebrew, November 2026). Read this
before trying again. Main reference: the MAME wiki page
[Driver:Apollo](https://wiki.mamedev.org/index.php/Driver:Apollo). It is
written for MAME 0.240 / ~2022 and is out of date in places, as noted below.

## Choosing the emulator

- **UTM can't do this.** UTM is QEMU, and QEMU's m68k target has no Apollo
  machine (only q800, next-cube, virt and ColdFire boards). MAME's `apollo`
  driver emulates DN3000/DN3500/DN5500 and the headless DSP variants.
- The **DN3500 has no serial console** in MAME 0.289. `-listslots` shows only
  ISA slots. The stdio console in `apollo.cpp` is behind `#ifdef APOLLO_XXL`
  and isn't compiled in. Driving the DN3500 means injecting keystrokes and
  reading screenshots.
- The **DSP3500** is the same board with the same boot ROM (it's a clone of
  `dn3500` in MAME) and a serial console on an `rs232` slot. It takes the same
  `.awd` disk and `.ani` node ID. **Do the install headless as a DSP3500**,
  then boot the result as a DN3500. See `tools/headless.sh`.

## Media

- bitsavers.org itself answers scripted requests with 403. The
  `ftp.mirrorservice.org/sites/www.bitsavers.org/` mirror works.
  `fetch-media.sh` uses it.
- MAME's ROM list for dn3500 includes `0729-12_a.3h` and `0729-62_a.3f`. They
  aren't loose files on bitsavers; they're inside `firmware/3c505.zip`.
- `3c505-nw.bin` is reported as missing ("NO GOOD DUMP KNOWN"). That's an
  optional NetWare boot PROM and is harmless. `-verifyroms` still says "best
  available".
- MAME's `hash/apollo_ctape.xml` has the SR10.4 set as software `domainos`,
  parts `cass1` (boot tape 019593-001) to `cass5` (019594-004). Files go in
  `roms/apollo_ctape/domainos/` with lowercase names, and `-ct domainos:cass1`
  works.

## Disk image and node ID (MAME 0.289 quirks)

- **Image paths must be absolute.** With relative paths MAME failed to open
  or create the images.
- **MAME won't create the `.awd` disk image** ("Unable to create image ...
  No such file or directory"), even though `omti_disk_image_device::call_create`
  exists. `run.sh` pre-creates it to match that code: 1223 cyl × 15 heads × 18
  sectors × 1056-byte sectors = **348,701,760 bytes, every byte 0x55**. On
  reset MAME picks the disk type from the size: ≥ 300,000 blocks is the
  348 MB Maxtor type, otherwise the 155 MB Micropolis.
- **Node ID `.ani` is a 32-byte PROM image**: ID in bytes 2/4/6 (MSB first),
  byte 30 = (b2+b4+b6) & 0xff. MAME only creates one itself when the file name
  is the hex node ID (e.g. `5A3E1.ani`). A failed create leaves a **0-byte
  file that then fails to load** ("Device Apollo Node ID load failed"), so
  delete it. `run.sh` writes the file itself (default ID `5A3E1`).

## Machine configuration

- Defaults are Service mode, "30 Years Ago" On, "25 Years Ago" On, "Node ID
  from Disk" On. The whole install ran on these defaults.
- **cfg file format: one `<port>` entry per config field.** A combined mask
  such as `mask="384"` is **silently ignored**. That's what MAME itself
  writes:

  ```xml
  <port tag=":apollo_config" type="CONFIG" mask="1" defvalue="0" value="1" />
  ```

  The simplest reliable way: set it at runtime from Lua
  (`manager.machine.ioport.ports[":apollo_config"].fields["Normal/Service"].user_value = 1`)
  and exit MAME cleanly so it saves the cfg.
- **Normal mode doesn't boot in MAME 0.289.** The screen stays black and the
  ROM spins at PC ≈ 0x67a2 polling the DUART at 0x10400. Stay in **Service
  mode** and let `tools/apollo.lua` type `ex domain_os` / `go`
  (`APOLLO_AUTOBOOT=1`, the default for `./run.sh boot`).

## The clock (solved by `tools/apollo.lua`)

- SR10.4 before 10.4.1 breaks after **2 Nov 1997**, so the Apollo clock has to
  stay before that.
- The wiki says to turn on "25 Years Ago". **In 2026 that does nothing.**
  `MACHINE_RESET` only adjusts the RTC year register if it's < 25 (adds 75)
  or, for 30 Years Ago, < 30 (adds 70).
- Root cause: **at every MAME start the MC146818 is loaded from host UTC time
  in whatever mode the saved NVRAM register B says.** Domain/OS keeps the RTC
  in **binary, 24-hour, UTC** (register B = `0x06`, year `0x60` = 1996).
  Fresh NVRAM is BCD/12-hour (B = `0x00`), so 2026 becomes `0x26`, which
  Domain/OS reads as "2003-09-xx". Getting it into binary mode needs a
  *clean* MAME exit after Domain/OS has set it: **`kill -9` skips the NVRAM
  save**, and that's how this kept coming back.
- Symptoms: the kernel stops with "More than 14 days have elapsed since the
  last shutdown" or "The calendar is more than a minute slow", then "Switch
  to service mode, press reset and run CALENDAR". It doesn't return to the
  MD; reset the machine (`reset` via the hook).
- **Fix:** on the first frame (and after every reset), `tools/apollo.lua`
  writes the RTC directly at physical 0x10900–0x1090B in Domain/OS's format
  with host UTC time minus `APOLLO_YEARS_BACK` (default 30). It sets bit 7 of
  register B while writing. Look for `clock set to 1996-...` in
  `state/ctape.log`. Around Nov 2027 the default lands past the bug date
  again; raise `APOLLO_YEARS_BACK` (keep it ≥ 1 day after the disk's last
  recorded time, or run `calendar` once).
- If you move the clock backwards relative to the disk, `calendar` warns
  about duplicate Unique IDs and salvol resets the "last mount" time. That's
  harmless for a fresh install.

## DN3500 keyboard injection (`tools/apollo.lua`)

- The Apollo keyboard has no natural-keyboard (PORT_CHAR) support, so
  `type <text>` presses ioport fields directly. Letters are `A`...`Z`,
  digits/symbols are names like `"1 !"`/`"- _"` (Shift for the second
  character), `Space`, and **Return is the unnamed field that Lua lists as
  `"Keyboard"`** (mask `0x20000000` in `:kbd:keyboard1`).
- Domain/OS drops presses only 2 frames long (the MD doesn't). Keys are now
  held about 8 frames.
- **The Display Manager ignores injected main Return; keypad Enter works.**
  In `type`, `\n` = Return (MD / bootshell), `\r` = keypad Enter (DM). On a
  Mac keyboard, fn+Return is keypad Enter if Return doesn't work for you.
- The DM sends keystrokes to the window under the cursor, and the host mouse
  over the MAME window moves it. Injected login only works when the cursor
  is in the login box.
- Autoboot timing (emulated seconds): CR at 2 s (the first line after reset
  is swallowed), `ex domain_os` at 4 s, `go` at 90 s. `go` at 30 s was too
  early; the `)` prompt appears somewhere between 30 and 75 s.
- Screenshots without the UI:
  `echo 'lua manager.machine.video:snapshot()' > state/ctape.req` →
  `state/snap/dn3500/NNNN.png`.

## Serial console over TCP (DSP3500)

- `-rs232 null_modem -bitb socket.127.0.0.1:2323`: MAME first tries to
  *connect*, logs "Unable to load image 'socket...': Connection refused", and
  then **listens** on that port. Connect after it starts. The error is noise.
- "Error instantiating layout view Terminal: invalid screen index 0" with
  `-video none` is also noise.
- The MD (boot monitor, "MD7C REV 8.00") **autobauds**. It prints nothing
  until it gets a CR, and **after `re` (reset) the first line you type is
  swallowed**. Send a bare CR, wait for the `MD7C ...` banner and `>`, then
  type the command.
- 9600 8N1 is the null_modem default and works. The MD has no flow control,
  so `tools/console.py` sends characters 10 ms apart.

## Boot monitor (MD) cheat sheet

| What                          | How                                                     |
|-------------------------------|---------------------------------------------------------|
| select tape / disk            | `di c` / `di w` (no output, just `>`)                    |
| run a program                 | `ex invol`, `ex calendar`, `ex salvol`, `ex domain_os`   |
| reset                         | `re` (then bare CR, see autobaud above)                  |
| "NO FILE I/O IN MAPPED MODE"  | a kernel ran since the last reset: `re` first            |
| "error: sysboot not found"    | wrong device selected, or see below                      |
| no help command               | `he` just prints `E`                                     |

- **After the base restore, `di w` + `ex domain_os` fails with "sysboot not
  found".** The restore puts `sysboot.m68k` on the disk, not `sysboot`.
  Presumably `minst` adds it; not confirmed yet. Workaround: boot from the
  tape (`di c`, `ex domain_os`) and answer **N** to "This program will replace
  system software on your disk. Do you wish to proceed? (Y/N)". You land at
  the RBAK `)` bootshell without touching the disk, and **`go`** brings the
  OS up from disk.
- If a boot is interrupted, the next boot says "BOOT VOLUME NEEDS
  SALVAGING. Proceed to bring up OS (and risk volume)?". Answer n, `re`, then
  `di c`, `ex salvol`, `w`, `1 -f`, and n to "Anything more to do?".

## invol / calendar answers that worked

`ex invol` (from tape):

1. `7` (init physical badspot list) → `w` → "Use automated badspot entry?"
   `n` → blank line (no badspots) → `y` → "Anything more" `y`
2. `1` (init virgin volume) → `w` → name `dn3500` → verification `1` (none) →
   avg file size: CR → volumes: `all, dn3500`, then blank line →
   "Use pre-recorded badspot info?" `yes` → formats → "Anything more" `y`
3. `8` (paging file) → `w` → lv `1` → size: CR (640 kB) → "Anything more" `n`

Prompts end in `]`, `:`, `?` or `(Y/N):`. "Use pre-recorded badspot info?"
wants a literal `yes`/`no`.

`ex calendar`: `w` → reset time zone `y` → `MST` (identifiers or `-7:00`)
→ reset date `y` → `1996/11/08` → `HH:MM` → `y`.

## Domain/OS first boot (DSP3500)

- `)` `go` → Init → "SPM system init complete. Node ID = ..." → SPM. Type
  `sh`, login `user`, empty password. "Registries unavailable. You are logged
  in as user.none.none." is normal before the registry exists.
- Log out with Ctrl-D. At the SPM, `shut` → "Shutdown successful" → back at
  the MD `>`. Only stop MAME after that.
- MAME didn't always exit on SIGTERM; `pkill -9 -f 'mame dsp3500'` once
  Domain/OS is shut down.

## minst (software tapes 1–4)

- The base system has almost no commands. `/com` holds about 19 Aegis tools
  (`ld`, `catf`, `cpf`...). There's no `ls`, and `rbak` is
  `/install/tools/rbak_sr10`.
- Rewind before swapping: `/install/tools/rbak_sr10 -dev ct -rewind`. **Under
  Domain/OS, swapping tapes mid-run through `apollo.lua` works fine**; only
  the MD got confused.
- `/install/tools/minst` answers: Return (intro) → `continue` → `novice` →
  Return (more text) → AA: Return (default `//node_xxxxx`) → target: Return
  → "install Domain/OS?" `yes` → media `ct` → "put volume 1" Return (tape
  019594-001 loaded) → release notes Return → template `11` (`large`) →
  `yes`.
- It then asks "Please insert volume N into the cartridge tape drive. Press
  <RETURN> when ready". Write tape N's path to `state/ctape.req`, then Return.
  Volume N is 019594-00N.
- After volume 4: release notes Return → "select Domain/OS version 10.4 or
  quit" `s` → install phase (hard links, soft links, X11 font metrics) →
  "RAI install has successfully completed".
- With `-nothrottle`, each software tape took **about 2–3 minutes** and the
  install phase about 10. Only the boot tape restore through RBAK_BS was slow
  (about 15 min).
- Expected warnings: two release-note docs (`bind4.8_operations_guide`,
  `software_release_bulletin.Z`) "Unable to install"; "mail: No group id of
  'mail'" at login.
- **After minst, `/sysboot` exists** and `di w` / `ex domain_os` / `go`
  boots from disk without a tape. `uname -a` →
  `DomainOS node_5a3 10.4 sys5.3 DSP3500`.

## Tapes and speed

- The SC-499 emulation reads at about real cartridge speed
  (`SC499_CTAPE_READ_BLOCK_TIME` = 6 ms per block). With `-nothrottle` the
  53 MB boot tape restore took about 15 minutes. MAME is single-threaded at
  100% CPU, so making it faster means rebuilding MAME with a smaller block
  time.
- Headless there's no UI File Manager to swap tapes. `tools/apollo.lua`
  (autoboot script) polls `state/ctape.req` each frame and loads the path
  written there (also accepts `unload`, `reset`, `hardreset`). Results go to
  `state/ctape.log`.
- **Swapping the tape while sitting at the MD left the SC-499 answering
  "Tape 39" (no drive)** on the next `di c`, and `re` didn't fix it.
  Restarting MAME with `-ct ...` did. The wiki says that under Domain/OS you
  should rewind/deselect first (`rbak -dev ct -rewind`) before swapping. Not
  yet tested under Domain/OS.
- SC-499 status codes the MD prints as `Tape NN ...`: 3a no cartridge,
  39 no drive, 38 end of media, 36/35/34 read errors, 31 filemark,
  30 illegal command.

## Lessons for automating this

- Don't wait only for the prompt you expect. `tools/tx.py` also stops on
  error-looking output and after `--idle` seconds of silence. Unexpected
  prompts (`]`, `(Y/N):`, an MD error followed by `>`) used to cause long
  silent stalls.
- Use short waits and re-poll (`tools/tx.py` with no text) for long tape
  jobs. Don't chain several steps in one command.
- To watch along: `tail -f state/console.log`.

## Status (2026-11-07)

- [x] Disk initialized, clock set, base system restored from the boot tape
- [x] Boots to SPM and login via tape bootshell (`N` → `)` → `go`)
- [x] `minst` with software tapes 019594-001..004 (template `large`)
- [x] Disk boots on its own (headless DSP3500); clean shutdown; backup copy in
      `disks/dn3500-sr10.4-installed.awd`
- [x] Durable clock fix (`tools/apollo.lua`)
- [x] DN3500 boots unattended (`./run.sh boot`) to the Display Manager; login
      as `user` with an empty password gives a shell pad
- [ ] Normal-mode autoboot (ROM hangs in MAME 0.289; worked around)
- [ ] Registry (`rgy_create`), networking
