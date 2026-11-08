#!/usr/bin/env bash
# With tools/headless.sh running and a shell logged in on the serial console:
# log out, shut Domain/OS down cleanly (back to the MD ">" prompt).
#
#   tools/dsp-shutdown.sh [--exit]     --exit also stops MAME cleanly

set -uo pipefail
cd "$(dirname "$0")/.."
TX="python3 -I tools/tx.py"

printf '\004' > state/console.in            # Ctrl-D: log out to the SPM
$TX '' -t 15 --idle 8 >/dev/null
out=$($TX 'shut' -t 300 -e '>\s*$' --idle 120)
case "$out" in
  *"Shutdown successful"*) echo "== shut down" >&2 ;;
  *) echo "dsp-shutdown: no 'Shutdown successful'" >&2; tail -10 state/console.log >&2; exit 1 ;;
esac

if [[ "${1:-}" == "--exit" ]]; then
  tools/req.sh 'lua manager.machine:exit()'
  while pgrep -x 'mame(-apollo)?' >/dev/null; do sleep 1; done   # -x: don't match this shell
  echo "== MAME exited" >&2
fi
