#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest scipy

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/voicemail.wav "Hey, it's me. The target motif is T T A C. For the reference dataset, the minimum value is zero and the maximum value is five."

    # Create the oracle script
    cat << 'EOF' > /app/oracle_model.py
import sys
import random
from scipy.stats import wasserstein_distance

def main():
    seq = sys.stdin.read().strip()
    if not seq:
        return
    random.seed(len(seq))

    MOTIF = "TTAC"
    MIN_VAL = 0
    MAX_VAL = 5

    scores = []
    for _ in range(1000):
        mutated = ""
        for char in seq:
            if random.random() < 0.05:
                mutated += 'A'
            else:
                mutated += char
        scores.append(mutated.count(MOTIF))

    ref_data = [random.randint(MIN_VAL, MAX_VAL) for _ in range(1000)]

    dist = wasserstein_distance(scores, ref_data)
    print(f"{dist:.4f}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
