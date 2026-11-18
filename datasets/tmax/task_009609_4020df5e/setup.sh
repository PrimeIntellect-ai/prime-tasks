#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user

    # Create target.seq
    echo -n "ATGCATGCATTTTTATGCATGCATTTTTCCCGGGAAATTTTTCCCGGGAAATTTTTCCCGGGAAATTTTTCCCGGGAAATTTTTGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGC" > /home/user/target.seq

    # Create background.seq
    echo -n "ATGCATGCATTTTTCCCGGGAAATTTTTCCCGGGAAAT" > /home/user/background.seq

    # Create candidates.txt
    cat << 'EOF' > /home/user/candidates.txt
ATGCATGCAT
CCCGGGAAAT
GCGCGCGCGC
AAAAATTTTT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
