# Domain/OS on an emulated Apollo DN3500

UTM/QEMU has no Apollo machine type, so this uses **MAME**, which emulates the
DN3500 (68030 @ 25 MHz, 4–32 MB RAM, OMTI 8621 ESDI controller, Archive SC-499
cartridge tape, 3Com 3C505 Ethernet, 8-plane colour display). MAME 0.289 is
installed via Homebrew (`brew install mame`) and runs natively on Apple silicon.

**Before trying the install, read [NOTES.md](NOTES.md).** It covers MAME
0.289 quirks, the broken clock, headless console tricks, and the answers to
every installer prompt.

## Layout

```
roms/                         boot ROMs (you supply these)
  dn3500.zip                  all six DN3500 + 3C505 ROM files (or split
                              the 3C505 ones into 3c505.zip)
  apollo_ctape/domainos/      Domain/OS SR10.4 install tapes (you supply these)
    019593-001.crtg_std_sfw_boot_1.ct
    019594-001.crtg_std_sfw_1.ct
    019594-002.crtg_std_sfw_2.ct
    019594-003.crtg_std_sfw_3.ct
    019594-004.crtg_std_sfw_4.ct
disks/                        hard disk image + node ID (created on first run)
state/                        MAME cfg / nvram / snapshots
run.sh                        launcher
```

The file names and checksums MAME expects are what `mame dn3500 -listroms` and
`hash/apollo_ctape.xml` list. ROMs and tape files can stay as loose files in
`roms/dn3500/` etc. instead of zips.

## Use

```bash
brew install mame
./fetch-media.sh        # download ROMs + SR10.4 tapes from bitsavers (not in git)
./run.sh check          # verify ROMs and tapes
./run.sh install 1      # boot with tape 1 (boot tape) in the drive
./run.sh boot           # boot from disk once installed
```

Defaults: 32 MB RAM, colour display, windowed. Override with
`RAM=8M`, `MACHINE=dn3500_19i` (19" mono), `NET=none` (no networking; by
default it attaches to `feth1` when that exists, see Networking).

## Using the Apollo

### Booting

```bash
./run.sh boot
```

A MAME window opens on the DN3500's 1024×800 screen. It boots by itself in
about 2–3 minutes:

1. The boot monitor `>` prompt appears, and `tools/apollo.lua` types
   `ex domain_os`.
2. The kernel loads and the `)` bootshell prompt appears. About 90 s
   (emulated) after start the script types `go`. **If it's still sitting at
   `)`, `go` arrived too early: click in the window, type `go` and press
   Return.**
3. Domain/OS starts, and the Display Manager (DM) shows `login:` in the input
   strip at the bottom of the screen.

### Logging in

- **The DM sends keystrokes to the window under the cursor.** Your Mac mouse
  moves the Apollo cursor while it's over the MAME window, so put it over the
  bottom input strip before typing.
- Log in as `user` or `root`, password **`-apollo-`**.
- If Return doesn't submit, use **fn+Return**, which sends keypad Enter. The
  DM reliably accepts that.
- After login you get a shell pad with a `$` prompt.

### Keyboard and mouse

- F1–F12 are the Apollo's special keys. They're labelled in the strip under the
  screen (F1 = SHELL/CMD, F11 = ABORT/EXIT...). On a Mac keyboard you may
  need to hold **fn** to send F-keys.
- Without options, the Apollo cursor just follows your mouse over the window.
  `./run.sh boot -mouse` makes MAME capture the pointer for proper Apollo
  mouse input. To get it back, switch to MAME's UI keys (UI Toggle, below)
  and press **P** to pause.

### Shutting down

Always shut Domain/OS down before closing the window. Otherwise the next boot
stops with "BOOT VOLUME NEEDS SALVAGING" and the disk has to be checked (see
NOTES.md).

1. Press **F1** (CMD) to get the DM command line.
2. Type `shut` and press Return.
3. Wait for the `>` boot monitor prompt, then close the MAME window.

Closing the window exits MAME cleanly, which saves its settings. Don't
`kill -9` it.

### Don't run two at once

`./run.sh boot` (DN3500 with display) and `tools/headless.sh` (DSP3500,
used for scripted maintenance) use **the same disk image**. Run only one at
a time.

### MAME keys

- The **UI toggle** key (Scroll Lock by default) switches between MAME's UI
  keys and full emulated keyboard. Mac keyboards have no Scroll Lock, so remap
  "UI Toggle" under Tab → Input Settings → User Interface. Domain/OS needs the full keyboard, so turn UI mode off while typing.
- **Tab** opens the MAME menu: *File Manager* to swap tapes 2–5 during install,
  *Machine Configuration* for Normal/Service mode and display type.

### Machine configuration

The DN3500 starts in **Service** mode by default and drops to the Mnemonic
Debugger (`>` prompt). **Leave it in Service mode**: Normal-mode autoboot
hangs in MAME 0.289. `./run.sh boot` types `ex domain_os` and `go` for you
instead (`APOLLO_AUTOBOOT=0` turns that off). "Node ID from Disk" is on by
default, and MAME keeps the node ID in `disks/dn3500-nodeid.ani`.

## Status

- [x] MAME 0.289, ROMs and SR10.4 tapes (`./fetch-media.sh`, checksums verified)
- [x] Domain/OS SR10.4 installed (template `large`), headless as a DSP3500
- [x] `./run.sh boot` brings a DN3500 up to the Display Manager on its own.
      Log in as `user` or `root`, password `-apollo-`. Use keypad Enter
      (fn+Return on a Mac) if Return doesn't submit.
- [x] Clock fixed to host time minus 30 years (SR10.4's Nov 1997 bug)
- [x] Registry (rgyd/glbd/rpcd) created
- [x] TCP/IP on a private Mac <-> Apollo link (Apollo 192.168.77.2,
      Mac 192.168.77.1); needs the patched MAME below

## Networking

Homebrew's MAME 0.289 can't receive network frames on macOS (its pcap backend
leaves out the Ethernet checksum the Apollo's chip checks; fixed upstream in
mamedev/mame#16741, after 0.289). Until Homebrew ships 0.290 or later, build
the patched Apollo-only MAME once, then bring the link up after each Mac
reboot:

```bash
tools/build-mame.sh
```

```bash
sudo tools/hostnet.sh up
```

```bash
./run.sh boot
```

The Apollo is then `192.168.77.2` (the Mac is `192.168.77.1`), running telnet,
rlogin, rsh and ftp. macOS doesn't ship a telnet client; `brew install telnet`,
then `telnet 192.168.77.2` and log in as `user` / `-apollo-`.

See [NOTES.md](NOTES.md) for how it all works and what was weird.
