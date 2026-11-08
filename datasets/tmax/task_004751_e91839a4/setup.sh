#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tar gzip gawk sed
    pip3 install pytest

    mkdir -p /home/user/dataset_work
    cd /home/user/dataset_work

    # Create the dummy metadata file
    cat << 'EOF' > metadata.txt
ID,Status,Temperature,Path
1,VALID,22.5,data/1.dat
2,CORRUPT,99.9,data/2.dat
3,VALID,26.1,data/3.dat
4,VALID,24.0,data/4.dat
5,INVALID,0.0,data/5.dat
6,VALID,24.2,data/6.dat
EOF

    # Create a tar.gz archive
    tar -czf measurements.tar.gz metadata.txt
    rm metadata.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
