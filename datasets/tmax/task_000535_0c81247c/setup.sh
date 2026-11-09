#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_data/raw_logs/

    # Generate 20 log files using seq to ensure compatibility with /bin/sh
    for i in $(seq -w 1 20); do
        log_file="/home/user/backup_data/raw_logs/server_${i}.log"

        # Write some standard logs
        for j in $(seq 1 50); do
            echo "2023-10-01 10:00:${j} [INFO] Standard operational log entry ${j} from server ${i}" >> "$log_file"
        done

        # Inject CRITICAL logs (deterministic count: 3 per file)
        echo "2023-10-01 10:01:00 [CRITICAL] Disk failure detected on /dev/sda in server ${i}" >> "$log_file"
        echo "2023-10-01 10:02:00 [CRITICAL] Memory corruption detected in bank 0 server ${i}" >> "$log_file"
        echo "2023-10-01 10:03:00 [CRITICAL] Unauthorized access attempt blocked on server ${i}" >> "$log_file"

        # Write more standard logs
        for j in $(seq 51 100); do
            echo "2023-10-01 10:04:${j} [DEBUG] Trace information ${j} from server ${i}" >> "$log_file"
        done

        # Compress the log file
        gzip "$log_file"
    done

    chmod -R 777 /home/user
