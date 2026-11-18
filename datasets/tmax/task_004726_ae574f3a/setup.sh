#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
pip3 install pytest numpy

mkdir -p /app

# Generate the audio specification file
espeak -w /app/specs.wav "Hey, for the new primer tool, the primer length should be exactly eight. For the statistics, use a fixed numpy random seed of one zero zero four two, exactly two thousand bootstrap iterations, and calculate the tenth and ninetieth percentiles."

# Create the oracle binary
cat << 'EOF' > /app/oracle_primer
#!/usr/bin/env python3
import sys
import numpy as np

def score(seq):
    return sum(2 for c in seq if c in 'GC') - sum(1 for c in seq if c in 'AT')

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    dna = sys.argv[1]
    k = 8
    if len(dna) < k:
        print("0\n0.0, 0.0")
        sys.exit(0)

    scores = [score(dna[i:i+k]) for i in range(len(dna) - k + 1)]
    best_score = max(scores)

    np.random.seed(10042)
    bootstraps = []
    for _ in range(2000):
        sample = np.random.choice(scores, size=len(scores), replace=True)
        bootstraps.append(np.mean(sample))

    lower = np.percentile(bootstraps, 10)
    upper = np.percentile(bootstraps, 90)

    print(best_score)
    print(f"{lower:.1f}, {upper:.1f}")
EOF

chmod +x /app/oracle_primer

# Create user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
