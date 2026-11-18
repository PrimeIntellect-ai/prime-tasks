#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar zip unzip
    pip3 install pytest

    mkdir -p /home/user/backups /home/user/unpacked_logs /home/user/tmp_setup
    cd /home/user/tmp_setup

    # Create test files
    echo "LOG_DATA_A_123" > f1.log
    echo "LOG_DATA_A_123" > f2.log
    echo "LOG_DATA_B_456" > f3.log
    echo "LOG_DATA_C_789" > f4.log
    echo "LOG_DATA_B_456" > f5.log
    ln -s f1.log sym1.log
    ln -s f3.log sym2.log

    # Create valid archives
    tar -czf web.tar.gz f1.log f2.log sym1.log
    zip db.zip f3.log f4.log
    tar -czf app.tar.gz f5.log sym2.log

    # Create a corrupted archive
    head -c 100 /dev/urandom > api.tar.gz

    # Create master archive
    tar -cf /home/user/backups/master_logs.tar web.tar.gz db.zip app.tar.gz api.tar.gz

    # Cleanup setup tmp
    cd /
    rm -rf /home/user/tmp_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
