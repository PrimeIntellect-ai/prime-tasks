#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/backups/raw_logs
    cd /home/user/backups

    # Create some dummy log files
    for i in 1 2 3 4 5; do
        for j in $(seq 1 100); do
            echo "INFO: Normal log entry $j" >> raw_logs/service_$i.log
        done
    done

    # Inject exact leaks
    echo "CREDENTIAL_LEAK: abcdef12345" >> raw_logs/service_1.log
    echo "CREDENTIAL_LEAK: hex99999999" >> raw_logs/service_1.log
    echo "CREDENTIAL_LEAK: qwertyuiop0" >> raw_logs/service_2.log
    echo "CREDENTIAL_LEAK: zxcvbnm0987" >> raw_logs/service_4.log
    for i in $(seq 1 10); do
        echo "CREDENTIAL_LEAK: leak_line_$i" >> raw_logs/service_5.log
    done

    cd raw_logs
    tar -czf ../app_logs.tar.gz *.log
    cd ..
    rm -rf raw_logs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
