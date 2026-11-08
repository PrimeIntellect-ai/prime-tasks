#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/target.fasta
>seq1_isothermal_target
GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
EOF

    chmod -R 777 /home/user
