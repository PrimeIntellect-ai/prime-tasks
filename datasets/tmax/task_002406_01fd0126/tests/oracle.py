#!/usr/bin/env python3
import sys

def recover(hex_str, index):
    if len(hex_str) != 48:
        return "ERROR"

    prefix = hex_str[:16]
    suffix = hex_str[32:]

    # Bytes 8-11 (chars 16-23)
    val1 = int(hex_str[16:24], 16)
    val1_fixed = (val1 - index) % (2**32)
    part1 = f"{val1_fixed:08x}"

    # Bytes 12-15 (chars 24-31)
    val2 = int(hex_str[24:32], 16)
    val2_fixed = val2 ^ 0xDEADBEEF
    part2 = f"{val2_fixed:08x}"

    print(prefix + part1 + part2 + suffix)

if __name__ == "__main__":
    recover(sys.argv[1], int(sys.argv[2]))
