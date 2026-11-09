#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Generate raw sequence
    cat << 'EOF' > /home/user/generate_seq.py
import numpy as np
np.random.seed(42)
seq = "".join(np.random.choice(['A', 'C', 'G', 'T'], size=1000000))
with open('/home/user/raw_sequence.txt', 'w') as f:
    f.write(seq)
EOF
    python3 /home/user/generate_seq.py
    rm /home/user/generate_seq.py

    # Create buggy script
    cat << 'EOF' > /home/user/integrate_mutation.py
import multiprocessing as mp
import numpy as np

def process_chunk(data_tuple):
    idx, chunk = data_tuple
    gc_counts = np.array([1.1 if b in 'GC' else 0.9 for b in chunk])
    cum_gc = np.cumsum(gc_counts)
    integral = np.trapz(np.sin(cum_gc))
    return integral

def main():
    with open('/home/user/raw_sequence.txt', 'r') as f:
        seq = f.read().strip()

    chunk_size = 50000
    chunks = [(i, seq[i:i+chunk_size]) for i in range(0, len(seq), chunk_size)]

    total_integral = 0.0

    with mp.Pool(processes=4) as pool:
        # BUG: unordered summation leads to floating-point drift
        for result in pool.imap_unordered(process_chunk, chunks):
            total_integral += result

    with open('/home/user/final_result.txt', 'w') as f:
        f.write(f"{total_integral:.12f}\n")

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /home/user
