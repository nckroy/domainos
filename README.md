# Domain/OS on an emulated Apollo DN3500

UTM/QEMU has no Apollo machine type, so this uses **MAME**, which emulates the
DN3500 (68030 @ 25 MHz, 4–32 MB RAM, OMTI 8621 ESDI controller, Archive SC-499
cartridge tape, 3Com 3C505 Ethernet, 8-plane colour display). MAME 0.289 is
installed via Homebrew (`brew install mame`) and runs natively on Apple silicon.

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
Debugger (`>` prompt). That's what you want for installing from tape. Once the
system is installed, switch to **Normal** in Machine Configuration so it
boots on its own. "Node ID from Disk" is on by default, and MAME keeps the
node ID in `disks/dn3500-nodeid.ani`.

## Status

- [x] MAME installed, DN3500 driver present, launcher written
- [x] Boot ROMs in `roms/dn3500/` and `roms/3c505/`, from bitsavers `bits/Apollo/firmware/`
- [x] SR10.4 install tapes in `roms/apollo_ctape/domainos/`, from bitsavers `bits/Apollo/SR10.4/`
      (all SHA1s match MAME's records; `./run.sh check` passes)
- [x] Boots to the Mnemonic Debugger `>` prompt with tape 1 loaded
- [ ] Disk formatted and Domain/OS installed

## Disk and node ID

MAME 0.289 won't create these files itself here, so `run.sh` creates them on
first run:

- `disks/dn3500-disk1.awd`: blank 348 MB Maxtor EXT-4380-E ESDI disk
  (1223 cyl × 15 heads × 18 sectors × 1056 bytes, filled with 0x55, as MAME's
  own create routine would).
- `disks/dn3500-nodeid.ani`: 32-byte node ID PROM. The node ID defaults to
  `5A3E1`. Set `NODE_ID=xxxxx` (hex) before the first run to pick another one.

Delete either file to start over.
