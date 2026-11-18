#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) < 2:
        print("0.0000")
        return
    seq = sys.argv[1].upper()
    if len(seq) == 0:
        print("0.0000")
        return

    gc_count = seq.count('G') + seq.count('C')
    x = gc_count / len(seq)

    alpha = 2.5
    beta = 0.2
    n = 2
    dt = 0.1

    for _ in range(100):
        dx = alpha * (1.0 / (1.0 + x**n)) - beta * x
        x = x + dt * dx

    print(f"{x:.4f}")

if __name__ == '__main__':
    main()
