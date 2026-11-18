#!/usr/bin/env python3
import sys
import re

def compute(path):
    m = re.match(r'^/load/([a-zA-Z0-9_]+)$', path)
    if not m:
        return "INVALID"
    module = m.group(1)
    A = 0
    for char in module:
        A = (A * 31 + ord(char)) % 256
    return f"http://ci-proxy.local/backend_{A}/{module}"

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("INVALID")
    else:
        print(compute(sys.argv[1]))
