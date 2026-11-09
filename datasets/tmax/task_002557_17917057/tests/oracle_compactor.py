#!/usr/bin/env python3
import sys
import struct

def main():
    target_app_id = 0x8BADF00D
    magic = sys.stdin.buffer.read(8)
    if not magic:
        return
    sys.stdout.buffer.write(magic)

    while True:
        header = sys.stdin.buffer.read(8)
        if len(header) < 8:
            break
        length, app_id = struct.unpack('<II', header)

        # Read the payload in chunks to simulate true streaming, though here we just read it
        payload = sys.stdin.buffer.read(length)

        if app_id != target_app_id:
            sys.stdout.buffer.write(header)
            sys.stdout.buffer.write(payload)

if __name__ == '__main__':
    main()
