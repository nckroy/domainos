# Agent notes

Read `NOTES.md` before touching the emulator. It records the MAME/Apollo
quirks, the prompt-by-prompt answers for `invol`, `calendar` and `salvol`,
and the current install status.

- Headless work (installs, maintenance) runs as a DSP3500 via
  `tools/headless.sh`. Drive the serial console with `tools/tx.py`, swap tapes
  through `state/ctape.req` (`tools/apollo.lua`).
- Never commit `roms/`, `disks/` or `state/` (copyrighted media, machine state).
- Use short waits and report progress; tape steps take 15+ minutes.
- Shut Domain/OS down (`shut` at the SPM) before stopping MAME, or the volume
  needs salvaging. Then stop MAME cleanly with
  `echo 'lua manager.machine:exit()' > state/ctape.req`, not `kill -9`, which
  skips the cfg/NVRAM save.
- For experiments on the DN3500, use a scratch disk: `DISK=state/test.awd ./run.sh boot`.
  The pristine post-install image is `disks/dn3500-sr10.4-installed.awd`.
