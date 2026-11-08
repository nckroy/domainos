#!/usr/bin/env bash
# With tools/headless.sh running: boot Domain/OS from disk on the DSP3500 and
# log in on the serial console, leaving a shell prompt.
#
#   tools/dsp-boot.sh [login] [password]     default: user, empty password
#
# Assumes the MD ">" prompt (fresh start, or after a clean "shut").

set -uo pipefail
cd "$(dirname "$0")/.."
TX="python3 -I tools/tx.py"
login="${1:-user}"
password="${2:-}"

step() { echo "== $*" >&2; }
fail() { echo "dsp-boot: $*" >&2; tail -15 state/console.log >&2; exit 1; }

step "waking MD"
for _ in 1 2 3 4; do
  $TX '' -t 8 -e 'REV.*\n>\s*$|^>\s*$' --idle 4 >/dev/null && break
done
$TX 'di w' -t 15 -e '>\s*$' --idle 8 >/dev/null || fail "no MD prompt"

step "loading kernel"
out=$($TX 'ex domain_os' -t 300 -e '(\)|\?)\s*$' --idle 200)
case "$out" in
  *SALVAGING*) fail "volume needs salvaging (see NOTES.md)";;
  *CALENDAR*)  fail "kernel wants CALENDAR (see NOTES.md, clock)";;
  *')'*)       ;;
  *)           fail "no bootshell prompt";;
esac

step "starting OS"
$TX 'go' -t 300 -e 'MBX_HELPER.*\s*$' --idle 120 --no-errors >/dev/null || fail "SPM did not come up"

step "logging in as $login"
$TX 'sh' -t 60 -e 'login:\s*$' --idle 30 >/dev/null || fail "no login prompt"
$TX -t 60 -e 'Password:\s*$' --idle 30 -- "$login" >/dev/null || fail "no password prompt"
$TX -t 180 -e '(\$|#)\s*$' --idle 120 --no-errors -- "$password" >/dev/null || fail "no shell prompt"
step "logged in"
