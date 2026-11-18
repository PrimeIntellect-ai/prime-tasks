#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
c1 = "A" * 25 + "G" * 25
c2 = "T" * 25 + "C" * 25
c3 = "G" * 40 + "A" * 10
c4 = "C" * 25 + "T" * 25
c5 = "A" * 40 + "G" * 10
fasta = f">seq1_part1\n{c1}{c2}\n>seq1_part2\n{c3}{c4}{c5}\n"
with open('/home/user/genome.fasta', 'w') as f:
    f.write(fasta)
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
