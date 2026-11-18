#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_etl_dump.txt
System is starting
SYSTEM IS STARTING
   System   is  starting
Processing data batch 1
Processing   data batch 1
Data batch 2 arrived
data BATCH 2 arrived
error in pipeline
ERROR   IN   PIPELINE
retrying batch 2
data batch 2 arrived
batch 3 processing
batch 3 processing
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
