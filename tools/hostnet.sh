#!/usr/bin/env bash
# Private Mac <-> Apollo Ethernet link using a macOS fake-ethernet pair.
#
#   sudo tools/hostnet.sh up      create feth0 (Mac, 192.168.77.1) <-> feth1 (Apollo side)
#   sudo tools/hostnet.sh down    remove them
#   tools/hostnet.sh status
#
# MAME attaches the Apollo's 3C505 to feth1 through pcap (/dev/bpf*), so "up"
# also gives the access_bpf group read/write on the BPF devices (what
# Wireshark's ChmodBPF does). Neither survives a Mac reboot; run "up" again.
#
# Apollo: 192.168.77.2 (node_5a3e1 / dn3500), netmask 255.255.255.0.

set -euo pipefail
MAC_IF=feth0
APOLLO_IF=feth1
MAC_IP=192.168.77.1

case "${1:-status}" in
  up)
    [[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
    ifconfig "$MAC_IF" >/dev/null 2>&1 || ifconfig "$MAC_IF" create
    ifconfig "$APOLLO_IF" >/dev/null 2>&1 || ifconfig "$APOLLO_IF" create
    ifconfig "$MAC_IF" peer "$APOLLO_IF" 2>/dev/null || true
    ifconfig "$MAC_IF" inet "$MAC_IP" netmask 255.255.255.0 up
    ifconfig "$APOLLO_IF" up
    chgrp access_bpf /dev/bpf*
    chmod g+rw /dev/bpf*
    echo "up: $MAC_IF $MAC_IP <-> $APOLLO_IF (Apollo 192.168.77.2)"
    ;;
  down)
    [[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
    ifconfig "$APOLLO_IF" destroy 2>/dev/null || true
    ifconfig "$MAC_IF" destroy 2>/dev/null || true
    echo down
    ;;
  status)
    ifconfig "$MAC_IF" 2>/dev/null | grep -E 'flags|inet |peer' || echo "$MAC_IF: not present"
    ifconfig "$APOLLO_IF" 2>/dev/null | grep -E 'flags|peer' || echo "$APOLLO_IF: not present"
    ls -l /dev/bpf0
    ;;
  *) sed -n '2,12p' "$0" >&2; exit 2 ;;
esac
