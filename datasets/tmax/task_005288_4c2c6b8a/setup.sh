#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    # Create target primer
    echo "ATGCGTACG" > target_primer.txt

    # Create generate_data.py
    cat << 'EOF' > generate_data.py
import json
import random
import math

random.seed(42)
fasta_out = open("database.fasta", "w")
spectra_dict = {}

bases = ['A', 'C', 'G', 'T']
for i in range(1, 501):
    seq_id = f"seq_{i:03d}"
    seq = "".join(random.choices(bases, k=50))
    fasta_out.write(f">{seq_id}\n{seq}\n")

    # Generate a noisy signal with a dominant frequency
    freq = random.uniform(1.0, 50.0)
    signal = [math.sin(2 * math.pi * freq * (t / 256.0)) + random.uniform(-0.1, 0.1) for t in range(256)]
    # Make magnitudes vary wildly to ensure float addition non-commutativity
    multiplier = 10 ** random.randint(-3, 5)
    signal = [s * multiplier for s in signal]
    spectra_dict[seq_id] = signal

fasta_out.close()
with open("spectra.json", "w") as f:
    json.dump(spectra_dict, f)
EOF
    python3 generate_data.py
    rm generate_data.py

    # Create the buggy script
    cat << 'EOF' > spectral_primer_score.py
import json
import numpy as np
from multiprocessing import Pool

def parse_fasta(filepath):
    seqs = {}
    with open(filepath, 'r') as f:
        curr_id = None
        curr_seq = []
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if curr_id:
                    seqs[curr_id] = "".join(curr_seq)
                curr_id = line[1:]
                curr_seq = []
            else:
                curr_seq.append(line)
        if curr_id:
            seqs[curr_id] = "".join(curr_seq)
    return seqs

def process_sequence(args):
    seq_id, seq, primer, signal = args

    # Simple alignment score: count occurrences of primer
    align_score = seq.count(primer)
    if align_score == 0:
        # Fallback to partial matches
        align_score = sum(1 for i in range(len(seq)-3) if seq[i:i+3] in primer) * 0.1

    # Process signal via FFT
    fft_vals = np.fft.fft(signal)
    max_amp = np.max(np.abs(fft_vals))

    return max_amp * align_score

def main():
    with open('target_primer.txt', 'r') as f:
        primer = f.read().strip()

    fasta_db = parse_fasta('database.fasta')
    with open('spectra.json', 'r') as f:
        spectra = json.load(f)

    tasks = []
    # Dictionary keys are ordered in Python 3.7+, but let's be explicit
    for seq_id, seq in fasta_db.items():
        tasks.append((seq_id, seq, primer, spectra[seq_id]))

    total_score = 0.0
    with Pool(4) as p:
        # BUG: imap_unordered yields results as soon as they finish, 
        # leading to non-deterministic summation order and float variance.
        for score in p.imap_unordered(process_sequence, tasks):
            total_score += score

    print(f"Total Score: {total_score}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
