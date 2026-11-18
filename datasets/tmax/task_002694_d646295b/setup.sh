#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/batch1
    mkdir -p /home/user/dataset/batch2
    mkdir -p /home/user/dataset/batch_valid
    mkdir -p /home/user/dataset/bad_links

    cat << 'EOF' > /home/user/dataset/batch1/data1.csv
record_id,experiment_name,status,measurement
105,expA,VALID,1.23
101,expA,ERROR,5.00
108,expA,VALID,0.05
EOF
    gzip /home/user/dataset/batch1/data1.csv

    cat << 'EOF' > /home/user/dataset/batch_valid/data2.csv
record_id,experiment_name,status,measurement
102,expB,VALID,4.5
110,expB,PENDING,0.0
103,expB,VALID,2.2
EOF
    gzip /home/user/dataset/batch_valid/data2.csv

    # Create valid symlink to batch_valid
    ln -s /home/user/dataset/batch_valid /home/user/dataset/batch2/link_to_valid

    # Create infinite symlink loop
    ln -s /home/user/dataset/bad_links /home/user/dataset/bad_links/loop

    chown -R user:user /home/user/dataset
    chmod -R 777 /home/user
