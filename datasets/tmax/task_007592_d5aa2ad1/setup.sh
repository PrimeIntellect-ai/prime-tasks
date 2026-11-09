#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user
    mkdir -p logs valid_logs corrupt_logs

    # Create valid log_01
    echo "Data 1" > dummy.txt && tar -czf logs/log_01.tar.gz dummy.txt

    # Create invalid log_02 (bad magic)
    echo "Not a gzip" > logs/log_02.tar.gz

    # Create valid log_03
    echo "Data 3" > dummy.txt && tar -czf logs/log_03.tar.gz dummy.txt

    # Create invalid log_04 (truncated tar)
    echo "Data 4" > dummy.txt && tar -czf logs/log_04_temp.tar.gz dummy.txt
    head -c 50 logs/log_04_temp.tar.gz > logs/log_04.tar.gz
    rm logs/log_04_temp.tar.gz

    # Create invalid log_05 (plain text)
    echo "Data 5" > logs/log_05.tar.gz

    rm dummy.txt

    chmod -R 777 /home/user
