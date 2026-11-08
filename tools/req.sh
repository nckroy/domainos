#!/usr/bin/env bash
# Send one request to tools/apollo.lua (running inside MAME) and wait until it
# has been picked up. Written atomically so the hook never sees half a line.
#
#   tools/req.sh dump | clock | reset | unload | <tape path> | 'type ...' | 'lua ...'

set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -ge 1 ]] || { sed -n '2,6p' "$0" >&2; exit 2; }
pgrep -x 'mame(-apollo)?' >/dev/null || { echo "req.sh: MAME is not running" >&2; exit 1; }
printf '%s\n' "$*" > state/ctape.req.tmp
mv state/ctape.req.tmp state/ctape.req
for _ in $(seq 1 100); do
  [[ -e state/ctape.req ]] || { tail -1 state/ctape.log; exit 0; }
  sleep 0.1
done
echo "req.sh: not picked up (MAME paused or exiting?)" >&2
exit 1
