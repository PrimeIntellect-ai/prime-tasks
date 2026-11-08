#!/usr/bin/env python3
import sys

invalid = {"NULL", "N/A", "UNKNOWN", "ERR", "DROP"}
threshold = 4.5

for line in sys.stdin:
    tokens = line.strip().split()
    valid_tokens = [t for t in tokens if t not in invalid]
    if not valid_tokens:
        print("REJECTED")
        continue
    avg_len = sum(len(t) for t in valid_tokens) / len(valid_tokens)
    if avg_len >= threshold:
        print(" ".join(valid_tokens))
    else:
        print("REJECTED")
