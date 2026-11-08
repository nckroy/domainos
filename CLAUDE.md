# Agent notes

Read `NOTES.md` before touching the emulator. It records the MAME/Apollo
quirks, the prompt-by-prompt answers for `invol`, `calendar` and `salvol`,
and the current install status.

- Headless work (installs, maintenance) runs as a DSP3500 via
  `tools/headless.sh`. `tools/dsp-boot.sh [login] [password]` boots and logs
  in; `tools/dsp-shutdown.sh [--exit]` shuts down cleanly. Drive the serial
  console with `tools/tx.py` (put text starting with `-` after `--`).
  Send hook requests (tapes, reset, `lua ...`) with `tools/req.sh`.
- Passwords: `root` and `user` are `-apollo-` (registry exists).
- Networking needs `build/mame-apollo` (`tools/build-mame.sh`) and
  `sudo tools/hostnet.sh up`. The sudo step is the user's; don't try to run
  it yourself.
- Wait for MAME with `pgrep -x 'mame(-apollo)?'`, never `pgrep -f 'mame ...'` (it matches
  your own shell).
- Never commit `roms/`, `disks/` or `state/` (copyrighted media, machine state).
- Use short waits and report progress; tape steps take 15+ minutes.
- Shut Domain/OS down (`shut` at the SPM) before stopping MAME, or the volume
  needs salvaging. Then stop MAME cleanly with
  `tools/req.sh 'lua manager.machine:exit()'`, not `kill -9`, which
  skips the cfg/NVRAM save.
- For experiments on the DN3500, use a scratch disk: `DISK=state/test.awd ./run.sh boot`.
  The pristine post-install image is `disks/dn3500-sr10.4-installed.awd`.
