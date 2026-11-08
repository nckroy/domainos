#!/usr/bin/env python3
"""Point the Apollo's 3C505 at a host interface in MAME's cfg file.

    tools/netcfg.py MACHINE IFACE        e.g. dn3500 feth1

MAME stores the chosen pcap interface as an index into its -listnetwork
order, so this looks the name up and rewrites the <network> element of
state/cfg/MACHINE.cfg (creating the file if needed). Run it while MAME is
not running for that machine, or MAME will overwrite it on exit.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

TAG = ":isa3:3c505:net"


def apollo_mac(machine: str) -> str:
    """Domain/OS programs the 3C505 with 08:00:1E + the 20-bit node ID, so
    MAME's pcap filter must use the same address or unicast frames to the
    Apollo are dropped (only broadcasts get through)."""
    ani = Path(__file__).resolve().parent.parent / "disks" / f"{machine.replace('dsp', 'dn')}-nodeid.ani"
    d = ani.read_bytes()
    return "08:00:1e:%02x:%02x:%02x" % (d[2] & 0x0f, d[4], d[6])


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    machine, iface = sys.argv[1], sys.argv[2]

    out = subprocess.run([os.environ.get("MAME", "mame"), "-networkprovider", "pcap", "-listnetwork"],
                         capture_output=True, text=True).stdout
    names = [l.strip() for l in out.splitlines()[1:] if l.strip()]
    if iface not in names:
        print(f"netcfg: {iface} not in MAME's interface list: {names}", file=sys.stderr)
        return 1
    index = names.index(iface)

    cfg = Path(__file__).resolve().parent.parent / "state" / "cfg" / f"{machine}.cfg"
    cfg.parent.mkdir(parents=True, exist_ok=True)
    s = cfg.read_text(encoding="utf-8-sig") if cfg.exists() else (
        '<?xml version="1.0"?>\n<mameconfig version="10">\n'
        f'    <system name="{machine}">\n    </system>\n</mameconfig>\n')

    mac = apollo_mac(machine)
    net = (f'        <network>\n            <device tag="{TAG}" interface="{index}" '
           f'mac="{mac}" />\n        </network>\n')
    s = re.sub(r'[ \t]*<network>.*?</network>\n', '', s, flags=re.S)
    s = s.replace('    </system>', net + '    </system>', 1)
    cfg.write_text(s, encoding="utf-8")
    print(f"netcfg: {machine} 3C505 -> {iface} (index {index}), mac {mac}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
