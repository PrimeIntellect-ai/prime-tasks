#!/usr/bin/env python3
import sys
import random
import numpy as np

def parse_fasta(path):
    with open(path, 'r') as f:
        lines = f.readlines()
    seq = ""
    for line in lines:
        if line.startswith(">"):
            if seq: break
            continue
        seq += line.strip()
    return seq

def count_bases(seq):
    seq = seq.upper()
    return seq.count('A'), seq.count('C'), seq.count('G'), seq.count('T')

def main():
    seq = parse_fasta(sys.argv[1])
    A, C, G, T = count_bases(seq)

    matrix = np.array([
        [2, 1, 1, 1],
        [1, 2, 1, 1],
        [1, 1, 2, 1],
        [1, 1, 1, 2]
    ], dtype=float)
    b = np.array([A, C, G, T], dtype=float)

    x, y, z, w = np.linalg.solve(matrix, b)

    random.seed(A + C + G + T)
    samples = [random.gauss(x, max(y, 1.0)) for _ in range(10000)]
    mc_mean = sum(samples) / 10000.0

    print(f"x: {x:.4f}, y: {y:.4f}, z: {z:.4f}, w: {w:.4f}, mc_mean: {mc_mean:.4f}")

if __name__ == "__main__":
    main()
