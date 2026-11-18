import sys
import numpy as np

def solve():
    seq = sys.stdin.read().strip()
    if not seq:
        return
    from itertools import product
    kmers = [''.join(p) for p in product('ACGT', repeat=3)]
    counts = {k: 0 for k in kmers}
    for i in range(len(seq) - 2):
        kmer = seq[i:i+3]
        if kmer in counts:
            counts[kmer] += 1

    matrix = np.zeros(64)
    for i, k in enumerate(kmers):
        matrix[i] = counts[k]
    matrix = matrix.reshape((8, 8))

    _, S, _ = np.linalg.svd(matrix)
    largest_sv = S[0]
    print(f"{largest_sv:.4f}")

if __name__ == '__main__':
    solve()
