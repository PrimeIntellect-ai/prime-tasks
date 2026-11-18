#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/binaries
    cp /bin/ls /home/user/dataset/binaries/exp_a.bin
    cp /bin/cat /home/user/dataset/binaries/exp_b.bin
    cp /bin/echo /home/user/dataset/binaries/exp_c.bin

    cat << 'EOF' > /home/user/dataset/metadata.csv
filename,experiment_id,temperature
exp_a.bin,EX-001,295K
exp_b.bin,EX-002,300K
exp_c.bin,EX-003,310K
EOF

    chown -R user:user /home/user/dataset
    chmod -R 777 /home/user
