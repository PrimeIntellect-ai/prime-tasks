#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gawk sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Setup required before the agent runs
    mkdir -p /home/user/storage/vol1
    mkdir -p /home/user/storage/vol2
    mkdir -p /home/user/incremental_backup

    # Create dummy binary artifacts
    echo -n "binarydataA_v1" > /home/user/storage/vol1/artA.bin
    echo -n "binarydataB_v2" > /home/user/storage/vol1/artB.bin
    echo -n "binarydataC_v1" > /home/user/storage/vol2/artC.bin
    echo -n "binarydataD_v3" > /home/user/storage/vol2/artD.bin

    # Create old_manifest.csv
    cat << 'EOF' > /home/user/old_manifest.csv
ART-001,/home/user/storage/vol1/artA.bin,1
ART-002,/home/user/storage/vol1/artB.bin,2
ART-003,/home/user/storage/vol2/artC.bin,1
EOF

    # Create raw_new_manifest.txt (Messy)
    cat << 'EOF' > /home/user/raw_new_manifest.txt
ART-001 , .\storage\vol1\artA.bin, 1
 ART-002, storage\vol1\artB.bin ,3
ART-003 ,/home/user/storage/vol2/artC.bin, 1
 ART-004 ,  .\storage\vol2\artD.bin , 1
EOF

    chmod -R 777 /home/user
