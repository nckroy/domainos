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
`RAM=8M`, `MACHINE=dn3500_19i` (19" mono), `NET=en0` (pcap networking).

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
      Log in as `user`, empty password. Use keypad Enter (fn+Return on a Mac)
      if Return doesn't submit.
- [x] Clock fixed to host time minus 30 years (SR10.4's Nov 1997 bug)
- [ ] Registry, networking

To shut down: press F1 (CMD) in the DM and type `shut`, wait for the `>`
prompt, then quit MAME.

See [NOTES.md](NOTES.md) for how it all works and what was weird.
