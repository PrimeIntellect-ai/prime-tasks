#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw
    mkdir -p /home/user/extracted

    touch /home/user/raw/sample1_read1.fq
    touch /home/user/raw/sample1_read2.fq
    touch /home/user/raw/sample2_read1.fq
    touch /home/user/raw/sample2_read2.fq
    touch /home/user/raw/unmapped_data.txt

    cd /home/user/raw
    tar -cvf /home/user/data_archive.tar ./*
    cd /home/user
    rm -rf /home/user/raw

    cat << 'EOF' > /home/user/mapping.ini
[Renames]
sample1 = patient_x
sample2 = patient_y
EOF

    chmod -R 777 /home/user
