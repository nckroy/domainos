#!/usr/bin/env bash
# Run the Apollo headless as a DSP3500 (same board and boot ROM as the
# DN3500, console on the serial port) against the same disk image, for
# scripted maintenance such as the Domain/OS install.
#
#   tools/headless.sh [extra MAME args...]     e.g. -ct domainos:cass1
#
# - serial console: MAME null_modem on 127.0.0.1:2323, bridged by
#   tools/console.py to state/console.log (output) and state/console.in (input);
#   use tools/tx.py to send a line and wait for a prompt
# - tape swaps: tools/apollo.lua (write a path to state/ctape.req)
# - runs unthrottled; stop it with: pkill -f 'mame dsp3500'

set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
# Patched Apollo-only MAME (tools/build-mame.sh) fixes pcap networking.
MAME="${MAME:-mame}"
[[ -x "$here/build/mame-apollo" && "$MAME" == mame ]] && MAME="$here/build/mame-apollo"
export MAME
mkdir -p state/cfg state/nvram state/snap
: > state/console.log
rm -f state/console.in state/ctape.req

# Networking: same rules as run.sh (NET=feth1 by default when it exists)
if [[ -z "${NET:-}" ]] && ifconfig feth1 >/dev/null 2>&1; then NET=feth1; fi
netprov=none
if [[ -n "${NET:-}" && "$NET" != none ]]; then
  python3 -I tools/netcfg.py dsp3500 "$NET" >&2
  netprov=pcap
fi

"$MAME" dsp3500 \
  -rompath "$here/roms" \
  -hashpath "$(brew --prefix mame)/share/mame/hash" \
  -cfg_directory "$here/state/cfg" \
  -nvram_directory "$here/state/nvram" \
  -snapshot_directory "$here/state/snap" \
  -ramsize "${RAM:-32M}" -skip_gameinfo \
  -video none -sound none -networkprovider "$netprov" -nothrottle \
  -ni "$here/disks/dn3500-nodeid.ani" \
  -disk1 "$here/disks/dn3500-disk1.awd" \
  -rs232 null_modem -bitb socket.127.0.0.1:2323 \
  -autoboot_script "$here/tools/apollo.lua" -autoboot_delay 0 \
  "$@" > state/mame.log 2>&1 &
mame_pid=$!

sleep 2
python3 -I tools/console.py &
bridge_pid=$!

trap 'kill $bridge_pid 2>/dev/null || true' EXIT
wait $mame_pid
