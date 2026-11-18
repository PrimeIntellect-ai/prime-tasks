#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/kmer_kl

    cat << 'EOF' > /home/user/reads.fasta
>read_1_perfect_match
ATGCGTACACGTACGTACGT
>read_2_1_mismatch_G_to_A
ATGCATACCCCGGGGAAAA
>read_3_perfect
ATGCGTACGGGGCC
>read_4_no_primer
NNNNNNN
>read_5_perfect_with_prefix
TTTATGCGTACAAAAAGGGG
>read_6_extra
ATGCGTACCCCCC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
