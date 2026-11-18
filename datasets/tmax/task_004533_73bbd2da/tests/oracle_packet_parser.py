#!/usr/bin/env python3
import sys

def parse():
    line = sys.stdin.read().strip()
    if not line:
        return
    if len(line) < 14:
        print("INVALID_HEADER")
        return

    try:
        version = int(line[0:2], 16)
        length = int(line[2:6], 16)
        timestamp = int(line[6:14], 16)
        payload_hex = line[14:]
    except ValueError:
        return

    actual_length = 7 + len(payload_hex) // 2
    if length != actual_length:
        print("LENGTH_MISMATCH")
        return

    payload_ascii = ""
    for i in range(0, len(payload_hex), 2):
        byte_val = int(payload_hex[i:i+2], 16)
        if 32 <= byte_val <= 126:
            payload_ascii += chr(byte_val)
        else:
            payload_ascii += "."

    print(f"V:{version} LEN:{length} TS:{timestamp} DATA:{payload_ascii}")

if __name__ == "__main__":
    parse()
