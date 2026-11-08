#!/usr/bin/env python3
"""Send a line to the Apollo console (via tools/console.py) and wait for output.

    tools/tx.py [-e REGEX] [-t SECONDS] [--idle SECONDS] [--raw] [TEXT]

Sends TEXT followed by CR (omit TEXT to just keep watching), then prints what
the Apollo writes until one of these happens:

  exit 0  REGEX matches the end of the new output (default: any prompt-ish
          line end: > ? : ) ] $ #) and output has been quiet for --quiet s
  exit 2  an error-looking line appears (error:, not found, Tape NN, abort...)
  exit 3  output has been idle for --idle seconds (something unexpected)
  exit 1  --timeout expired while output was still flowing

Waits are short by default; for long jobs call it again with no TEXT.
"""

import argparse
import os
import re
import stat
import sys
import time

LOG = "state/console.log"
FIFO = "state/console.in"
PROMPT = r"(>|\?|:|\)|\]|\$|#)\s*$"
ERRORS = r"(?im)^.*(error:|not found|\bTape \d+\s+[0-9A-F]{6}|aborted|\?\(.*\)|fatal|status [0-9a-f]{8}).*$"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("text", nargs="?")
    ap.add_argument("-e", "--expect", default=PROMPT)
    ap.add_argument("-t", "--timeout", type=float, default=90)
    ap.add_argument("--idle", type=float, default=45)
    ap.add_argument("--quiet", type=float, default=1.5,
                    help="seconds of silence required after a prompt match")
    ap.add_argument("--raw", action="store_true", help="don't append CR")
    ap.add_argument("--no-errors", action="store_true")
    args = ap.parse_args()

    # Wait for tools/console.py to create its FIFO; writing to a missing path
    # would create a regular file that the bridge never reads.
    t_wait = time.time() + 30
    while not (os.path.exists(FIFO) and stat.S_ISFIFO(os.stat(FIFO).st_mode)):
        if time.time() > t_wait:
            print(f"tx.py: {FIFO} is not a FIFO; is tools/console.py running?", file=sys.stderr)
            return 4
        time.sleep(0.2)

    start = os.path.getsize(LOG)
    if args.text is not None:
        with open(FIFO, "w") as f:
            f.write(args.text if args.raw else args.text + "\n")

    pat = re.compile(args.expect, re.M)
    err = re.compile(ERRORS)
    t0 = time.time()
    last_size, last_change = start, t0
    out = ""
    rc = 1
    while time.time() - t0 < args.timeout:
        size = os.path.getsize(LOG)
        now = time.time()
        if size != last_size:
            last_size, last_change = size, now
        with open(LOG, "rb") as f:
            f.seek(start)
            out = f.read().decode("latin-1")
        quiet = now - last_change
        if not args.no_errors and err.search(out) and quiet >= args.quiet:
            rc = 2
            break
        if pat.search(out) and quiet >= args.quiet:
            rc = 0
            break
        if quiet >= args.idle:
            rc = 3
            break
        time.sleep(0.2)
    sys.stdout.write(out)
    note = {0: "", 1: "timeout, still running", 2: "ERROR seen", 3: "idle, no prompt"}[rc]
    if note:
        sys.stdout.write(f"\n[tx.py: {note}, {time.time() - t0:.0f}s]\n")
    return rc


if __name__ == "__main__":
    sys.exit(main())
