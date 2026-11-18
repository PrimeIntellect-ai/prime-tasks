#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import random

def generate_fasta(filename, num_seqs, num_amplified):
    random.seed(hash(filename)) # Stable random generation based on filename
    bases = ['A', 'C', 'G', 'T']

    with open(filename, 'w') as f:
        for i in range(num_seqs):
            f.write(f">seq_{i}\n")

            is_amplified = i < num_amplified

            if is_amplified:
                # Need forward primer "ATGCGT", gap of 10-100, then "TGCGTA"
                prefix_len = random.randint(10, 50)
                gap_len = random.randint(10, 100)
                suffix_len = random.randint(10, 50)

                prefix = "".join(random.choices(bases, k=prefix_len))
                gap = "".join(random.choices(bases, k=gap_len))
                suffix = "".join(random.choices(bases, k=suffix_len))

                seq = prefix + "ATGCGT" + gap + "TGCGTA" + suffix
            else:
                # Just random sequences
                seq_len = random.randint(100, 200)
                seq = "".join(random.choices(bases, k=seq_len))
                # Ensure accidental amplification is removed (highly unlikely but just in case)
                seq = seq.replace("ATGCGT", "AAAAAA")

            f.write(seq + "\n")

generate_fasta('/home/user/reference.fasta', 100, 10)
generate_fasta('/home/user/mutants.fasta', 100, 60)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
