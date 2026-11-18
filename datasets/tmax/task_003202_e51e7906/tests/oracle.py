#!/usr/bin/env python3
import sys
import math
import json
import numpy as np

def kahan_sum(elements):
    sum_val = 0.0
    c = 0.0
    for e in elements:
        y = e - c
        t = sum_val + y
        c = (t - sum_val) - y
        sum_val = t
    return sum_val

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    seq = sys.argv[1]

    with open('/app/freqs.json', 'r') as f:
        freqs = json.load(f)

    signal = []
    for i in range(1024):
        t = i / 1023.0
        elements = [math.sin(2 * math.pi * freqs[aa] * t) for aa in seq]
        signal.append(kahan_sum(elements))

    fft_res = np.fft.rfft(signal)
    mags = np.abs(fft_res)
    print(np.max(mags))

if __name__ == "__main__":
    main()
