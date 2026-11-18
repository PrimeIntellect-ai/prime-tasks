#!/usr/bin/env python3
import sys
import argparse
import fcntl
import os
import time
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lockfile', type=str, default=None)
    parser.add_argument('--search', type=str, default=None)
    args, unknown = parser.parse_known_args()

    if args.search:
        target_dir = Path(args.search)
        if not target_dir.exists():
            return
        now = time.time()
        matches = []
        for path in target_dir.rglob('*.log'):
            try:
                mtime = path.stat().st_mtime
                if now - mtime <= 48 * 3600:
                    matches.append(str(path.absolute()))
            except FileNotFoundError:
                pass
        for m in sorted(matches):
            print(m)
        return

    lock_fd = None
    if args.lockfile:
        lock_fd = os.open(args.lockfile, os.O_CREAT | os.O_RDWR)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)

    try:
        for line in sys.stdin:
            stripped = line.rstrip('\n\r')
            if stripped.endswith(';'):
                # Replace ALPHA with BETA
                replaced = line.replace('ALPHA', 'BETA')
                sys.stdout.write(replaced)
            else:
                sys.stdout.write(line)
    finally:
        if lock_fd is not None:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)

if __name__ == '__main__':
    main()
