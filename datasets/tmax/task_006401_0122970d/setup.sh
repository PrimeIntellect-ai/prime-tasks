#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>Seq1_Low
ATGCATGCATGC
>Seq2_High
GCGCGCGCGCGC
>Seq3_Low
ATATATATATAT
>Seq4_High
GGGCCCCGGGCC
>Seq5_Border
GGCCTTAG
>Seq6_Normal
ATGCATGCGCAT
EOF

    cat << 'EOF' > /home/user/calc_gc.py
#!/usr/bin/env python3
import sys

def gc_content(seq):
    seq = seq.upper()
    valid_chars = [c for c in seq if c in 'ATGC']
    if not valid_chars:
        return 0.0
    gc_count = valid_chars.count('G') + valid_chars.count('C')
    return gc_count / len(valid_chars)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(1)

    with open(sys.argv[1], 'r') as f:
        lines = f.readlines()
        if not lines:
            sys.exit(0)

        seq_id = lines[0].strip().lstrip('>')
        sequence = ''.join(l.strip() for l in lines[1:])

        ratio = gc_content(sequence)
        print(f"{seq_id}\t{ratio:.4f}")
EOF

    chmod +x /home/user/calc_gc.py

    chmod -R 777 /home/user
