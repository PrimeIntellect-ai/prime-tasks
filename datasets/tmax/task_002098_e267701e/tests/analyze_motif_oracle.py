import sys
import math

def fit_predict(seq):
    pseudocount = 0.01
    counts = {'A':0, 'C':0, 'G':0, 'T':0}
    for c in seq:
        if c in counts:
            counts[c] += 1

    res = []
    for i in range(len(seq)):
        val = 0.0
        for c in "ACGT":
            val += math.exp(math.log(counts[c] + pseudocount + 0.0001))
        res.append(val / (i + 1.0))
    return res

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(1)
    seq = sys.argv[1]
    res = fit_predict(seq)
    print("Posterior: " + ",".join(f"{x:.4f}" for x in res))
