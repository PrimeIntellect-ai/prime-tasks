#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/reference.fasta
>seq1_reference_genome
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
GATTACAGATTACAGATTACAGATTACAGATTACAGATTA
CCCGGGAAATTTCCCGGGAAATTTCCCGGGAAATTTCCCG
GATTACAGATTACAGATTACAGATTACAGATTACAGATTA
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF
    chmod 644 /home/user/reference.fasta

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
