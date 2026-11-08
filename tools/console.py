#!/usr/bin/env python3
"""Bridge an Apollo DSP3500 serial console (MAME null_modem on a TCP socket)
to a log file and a FIFO, so it can be driven from a shell or script.

    tools/console.py [--port 2323] [--log state/console.log] [--fifo state/console.in]

Everything the Apollo prints is appended to the log (CRs stripped).
Whatever is written to the FIFO is sent to the Apollo, with LF turned into CR:

    printf 'ex invol\n' > state/console.in
"""

import argparse
import os
import selectors
import socket
import sys
import time


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=2323)
    ap.add_argument("--log", default="state/console.log")
    ap.add_argument("--fifo", default="state/console.in")
    ap.add_argument("--char-delay", type=float, default=0.01,
                    help="seconds between characters sent (the MD has no flow control)")
    args = ap.parse_args()

    if not os.path.exists(args.fifo):
        os.mkfifo(args.fifo)
    # O_RDWR keeps the FIFO open between writers, so we never see EOF.
    fifo = os.open(args.fifo, os.O_RDWR | os.O_NONBLOCK)

    deadline = time.time() + 60
    while True:
        try:
            sock = socket.create_connection((args.host, args.port), timeout=5)
            break
        except OSError:
            if time.time() > deadline:
                print("console.py: could not connect to MAME", file=sys.stderr)
                return 1
            time.sleep(0.5)
    sock.setblocking(False)

    log = open(args.log, "ab", buffering=0)
    sel = selectors.DefaultSelector()
    sel.register(sock, selectors.EVENT_READ, "sock")
    sel.register(fifo, selectors.EVENT_READ, "fifo")

    while True:
        for key, _ in sel.select():
            if key.data == "sock":
                data = sock.recv(65536)
                if not data:
                    return 0
                log.write(data.replace(b"\r", b""))
            else:
                data = os.read(fifo, 65536)
                for b in data.replace(b"\n", b"\r"):
                    sock.sendall(bytes([b]))
                    time.sleep(args.char_delay)


if __name__ == "__main__":
    sys.exit(main())
