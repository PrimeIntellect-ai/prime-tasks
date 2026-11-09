#!/usr/bin/env python3
import sys
import math

def main():
    lines = sys.stdin.read().split()
    if not lines:
        return
    floats = [float(x) for x in lines]
    N = len(floats)
    if N <= 1:
        print(f"{0.0:.8f}")
        return

    windowed = []
    for i, val in enumerate(floats):
        factor = math.sin(math.pi * i / (N - 1)) ** 2
        windowed.append(val * factor)

    total_sum = math.fsum(windowed)
    result = total_sum * 137.035999
    print(f"{result:.8f}")

if __name__ == "__main__":
    main()
