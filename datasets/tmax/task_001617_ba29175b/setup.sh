#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sequence.fasta
>sequence_1
ATGCGTACGATCGTAGCTAGCTAGCATCGATCGATCGATCGTACGATCGTAGCTAGCTAGCATCGATCGATCGATCGTACGATCGTAGCTAGCTAGCATCGATCGATCGATC
EOF

    cat << 'EOF' > /home/user/analyze_kmers.sh
#!/bin/bash
# analyze_kmers.sh
# Computes 3-mer transition frequencies

awk -v k=3 '
/^>/ {next}
{
    seq = seq $0;
}
END {
    # BUG: incorrect step size causes the sliding window to jump
    for(i=1; i<=length(seq)-k; i+=k) {
        k1 = substr(seq, i, k);
        k2 = substr(seq, i+1, k);
        transitions[k1 SUBSEP k2]++
    }

    # Print logic missing or incomplete
}' "$1"
EOF

    chmod +x /home/user/analyze_kmers.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
