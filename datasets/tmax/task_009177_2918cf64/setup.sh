#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user/bio_profiling
    cd /home/user/bio_profiling

    # Create dummy FASTA file
    cat << 'EOF' > sequences.fasta
>seq1
ATGCGTACGTAGCTAGCTAGCTAGCTGATCGA
>seq2
CGATCGATCGATCGATCGATCGATCGATCGAT
>seq3
ATATATATATATATATATATATATATATATAT
>seq4
GCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGC
>seq5
ATGCATGCATGCATGCATGCATGCATGCATGC
EOF

    # Create the unoptimized Python script
    cat << 'EOF' > primer_sim.py
import json
import time
import math

def read_fasta(filepath):
    sequences = {}
    with open(filepath, 'r') as f:
        name = ""
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                name = line[1:]
                sequences[name] = ""
            else:
                sequences[name] += line
    return sequences

def gc_content(seq):
    return sum(1 for c in seq if c in 'GC') / len(seq)

# BOTTLENECK 1: Inefficient nonlinear root finding (naive bisection with high iteration limit)
def calculate_tm_slow(gc, length):
    # Thermodynamic parameters (dummy)
    dH = -35000 - (gc * 10000)
    dS = -100 - (gc * 10)
    R = 1.987
    C = 1e-6

    # Equation to solve for T: dH - T*dS + R*T*ln(C) = 0
    def f(T):
        return dH - T*dS + R*T*math.log(C)

    # Naive bisection
    low, high = 200.0, 400.0
    for _ in range(1000000): # Horribly slow intentional bottleneck
        mid = (low + high) / 2.0
        val = f(mid)
        if abs(val) < 1e-7:
            return mid
        if f(low) * val < 0:
            high = mid
        else:
            low = mid
    return (low + high) / 2.0

# BOTTLENECK 2: Naive numerical integration (Riemann sum with 10 million steps)
def integrate_efficiency_slow(tm):
    # Integrate a Gaussian binding efficiency curve around Tm from T=250 to T=350
    a, b = 250.0, 350.0
    steps = 2000000 # Horribly slow intentional bottleneck
    dx = (b - a) / steps
    total = 0.0
    for i in range(steps):
        x = a + i * dx
        # Gaussian curve: exp(-((x - tm)**2) / 50)
        total += math.exp(-((x - tm)**2) / 50.0) * dx
    return total

def main():
    start_time = time.time()
    seqs = read_fasta("sequences.fasta")

    results = {}
    for name, seq in seqs.items():
        gc = gc_content(seq)
        tm = calculate_tm_slow(gc, len(seq))
        eff = integrate_efficiency_slow(tm)
        results[name] = {"tm": tm, "efficiency": eff}

    with open("results.json", "w") as f:
        json.dump(results, f, indent=4)

    print(f"Completed in {time.time() - start_time:.2f} seconds")

if __name__ == "__main__":
    main()
EOF

    # Pre-generate the expected results.json using the slow script
    python3 primer_sim.py
    mv results.json expected_results.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
