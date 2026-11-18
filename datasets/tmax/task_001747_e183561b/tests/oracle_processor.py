#!/usr/bin/env python3
import sys

def main():
    line = sys.stdin.read().strip()
    if not line: return
    samples = [int(x) for x in line.split(',')]
    out = [(s * 15420) // 256 for s in samples]
    print(','.join(map(str, out)))

if __name__ == '__main__':
    main()
