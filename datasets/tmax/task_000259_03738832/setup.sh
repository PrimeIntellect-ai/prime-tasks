#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/device_info.csv
DeviceID,Architecture,BaseMemory
DEV1,ARM64,8GB
DEV2,x86,16GB
DEV3,ARM64,4GB
DEV4,RISCV,2GB
DEV5,ARM64,8GB
EOF

    cat << 'EOF' > /home/user/inference_logs.csv
LogID,DeviceID,MatrixSize,InferenceTimeMS
L1,DEV1,1024,15.5
L2,DEV2,2048,120.0
L3,DEV1,-100,5.0
L4,DEV3,512,2.1
L5,DEV1,1024,16.2
L6,DEV4,256,0.8
L7,DEV5,1024,14.9
L8,DEV3,512,-2.0
L9,DEV5,2048,125.4
EOF

    chmod -R 777 /home/user
