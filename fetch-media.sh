#!/usr/bin/env bash
# Download the DN3500 boot ROMs and the Domain/OS SR10.4 install tapes from
# the bitsavers archive (via the mirrorservice.org mirror), unpack them into
# roms/ under the names MAME expects, and verify SHA1s against MAME's records.
#
# About 78 MB to download, 275 MB unpacked.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
R="$here/roms"
B="${BITSAVERS:-https://ftp.mirrorservice.org/sites/www.bitsavers.org/bits/Apollo}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

get() { echo "  $1" >&2; curl -sSfL --retry 3 -o "$work/$(basename "$1")" "$B/$1"; }

echo "Downloading from $B" >&2
get firmware/3500_BOOT_12191_7.bin
get firmware/3c505.zip
get SR10.4/019593-001.CRTG_STD_SFW_BOOT_1-REV.A.ct.gz
for n in 1 2 3 4; do get "SR10.4/019594-00$n.CRTG_STD_SFW_$n.ct.gz"; done

mkdir -p "$R/dn3500" "$R/3c505" "$R/apollo_ctape/domainos"
cp "$work/3500_BOOT_12191_7.bin" "$R/dn3500/3500_boot_12191_7.bin"
unzip -o -q "$work/3c505.zip" -d "$R/3c505"
gunzip -c "$work/019593-001.CRTG_STD_SFW_BOOT_1-REV.A.ct.gz" \
  > "$R/apollo_ctape/domainos/019593-001.crtg_std_sfw_boot_1.ct"
for n in 1 2 3 4; do
  gunzip -c "$work/019594-00$n.CRTG_STD_SFW_$n.ct.gz" \
    > "$R/apollo_ctape/domainos/019594-00$n.crtg_std_sfw_$n.ct"
done

echo "Verifying" >&2
(cd "$R" && shasum -a1 -c) <<'EOF'
36f3c83d9f2df42f2537b09ca2f051a8c9dfbfc2  dn3500/3500_boot_12191_7.bin
6a42d7f3acdb3e0213e1037fee1864819ac33991  3c505/0729-12_a.3h
015d2f7282def85681bcf1a7c5a7f501a16d5a6c  3c505/0729-62_a.3f
7ac36cc6fc90b90ddfc56c45303b514cbe18ae58  3c505/3000_3c505_010728-00.bin
ca5ddcb272ab2851e00473dc960b23039746e3d2  3c505/3com.9h
fe4c26b6a41e643f4397990b066fdc04b6f4c5ae  3c505/apollo.9h
4b7e64153b3046da25cef0e2115553611d57929e  apollo_ctape/domainos/019593-001.crtg_std_sfw_boot_1.ct
94ce5ea3f9d075df7952793254ef067b92df79a6  apollo_ctape/domainos/019594-001.crtg_std_sfw_1.ct
6cde13fae598574b4f5ad0fc4dbb33ea1902ff6e  apollo_ctape/domainos/019594-002.crtg_std_sfw_2.ct
24fe96a22c975e9c7fcbbf0daad89277a467fae3  apollo_ctape/domainos/019594-003.crtg_std_sfw_3.ct
a3b4eb922182302e350f475b8e5c39a79503c4e3  apollo_ctape/domainos/019594-004.crtg_std_sfw_4.ct
EOF
