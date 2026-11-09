#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/logs
    cd /home/user/logs

    # Create infinite symlink loop
    ln -s . loop_link

    # Create 50 fragmented log files
    for i in $(seq 1 50); do
        # zero-pad to ensure standard length
        num=$(printf "%03d" $i)
        echo "CRITICAL_LOG_ENTRY_${num}: System state stable at timestamp ${num}000" > "syslog_${num}.part"
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
