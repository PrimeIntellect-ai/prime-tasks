#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sequences.fasta
>protein_1
MKTAYR
>protein_2
ACDKRGP
EOF

    cat << 'EOF' > /home/user/data/ms_peaks.csv
peak_intensity
21.5
19.8
22.1
18.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
