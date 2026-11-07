#!/usr/bin/env bash
# Launch an emulated Apollo DN3500 (Motorola 68030) under MAME.
#
#   ./run.sh check            verify ROMs and install tapes are in place
#   ./run.sh install [N]      boot with install tape N (1-5, default 1) loaded
#   ./run.sh boot             boot from the hard disk (no tape)
#
# Extra arguments after the mode are passed straight to MAME, e.g.
#   ./run.sh boot -window -nomaximize
#
# Environment knobs:
#   RAM=32M        4M, 8M (MAME default), 16M or 32M
#   MACHINE=dn3500 or dn3500_19i for the 19" monochrome display
#   NET=en0        attach the 3C505 Ethernet card to a host interface via pcap
#                  (needs /dev/bpf* access, e.g. Wireshark's ChmodBPF helper)

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

MACHINE="${MACHINE:-dn3500}"
RAM="${RAM:-32M}"
DISK="$here/disks/${MACHINE%%_*}-disk1.awd"
NODEID="$here/disks/${MACHINE%%_*}-nodeid.ani"
NODE_ID="${NODE_ID:-5A3E1}"   # 20-bit hex Apollo node ID (only used on first run)

# Node ID PROM image as apollo_ni::call_load expects it: 32 bytes, ID in bytes
# 2/4/6 (MSB first), byte 30 = (b2+b4+b6) & 0xff.
if [[ ! -s "$NODEID" ]]; then
  echo "Creating node ID PROM $NODEID with node ID $NODE_ID" >&2
  perl -e '$n = hex shift; @d = (0) x 32;
           @d[2,4,6] = (($n>>16)&0xff, ($n>>8)&0xff, $n&0xff);
           $d[30] = ($d[2]+$d[4]+$d[6]) & 0xff;
           print pack("C*", @d)' "$NODE_ID" > "$NODEID"
fi

# MAME 0.289 fails to create the OMTI disk image itself, so pre-create it the
# way omti_disk_image_device::call_create would: a Maxtor EXT-4380-E
# (1223 cyl x 15 heads x 18 sectors x 1056-byte sectors = 348,701,760 bytes),
# every byte 0x55. MAME picks the 348 MB disk type from the file size.
if [[ ! -s "$DISK" ]]; then
  echo "Creating blank 348 MB disk image $DISK" >&2
  perl -e '$b = "\x55" x (1056*18); print $b for 1 .. 1223*15' > "$DISK"
fi

mode="${1:-boot}"
[[ $# -gt 0 ]] && shift

common=(
  "$MACHINE"
  -rompath "$here/roms"
  -hashpath "$(brew --prefix mame)/share/mame/hash"
  -cfg_directory "$here/state/cfg"
  -nvram_directory "$here/state/nvram"
  -snapshot_directory "$here/state/snap"
  -state_directory "$here/state/sta"
  -diff_directory "$here/state/diff"
  -ramsize "$RAM"
  -skip_gameinfo
  -window -nomaximize
  -ni "$NODEID"
  -disk1 "$DISK"
)

if [[ -n "${NET:-}" ]]; then
  common+=(-networkprovider pcap)
  echo "Networking via pcap on $NET: pick the interface in MAME's Network Devices menu (Tab key)." >&2
else
  common+=(-networkprovider none)
fi

case "$mode" in
  check)
    mame "$MACHINE" -rompath "$here/roms" -verifyroms
    mame -rompath "$here/roms" \
         -hashpath "$(brew --prefix mame)/share/mame/hash" \
         -verifysoftlist apollo_ctape
    ;;
  install)
    tape="${1:-1}"
    [[ $# -gt 0 ]] && shift
    exec mame "${common[@]}" -ct "domainos:cass${tape}" "$@"
    ;;
  boot)
    exec mame "${common[@]}" "$@"
    ;;
  *)
    sed -n '2,16p' "$0" >&2
    exit 2
    ;;
esac
