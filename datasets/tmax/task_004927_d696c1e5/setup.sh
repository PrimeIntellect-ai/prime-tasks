#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/access_log.csv
Alice,App1
App1,DataLake
DataLake,SecureVault
Bob,App2
App2,App1
Charlie,SecureVault
Dave,ServiceA
ServiceA,ServiceB
ServiceB,ServiceC
ServiceC,SecureVault
Eve,ServiceB
Frank,Frank
EOF
    chmod 644 /home/user/access_log.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
