#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs_raw
    mkdir -p /home/user/organized_logs

    # Create raw logs
    cat << 'EOF' > /home/user/logs_raw/app_1.log
2023-10-15T10:00:00Z [INFO] Service started
2023-10-15T10:05:12Z [WARN] Memory usage at 80%
2023-10-15T10:12:34Z [ERROR] Database timeout occurred
2023-10-15T10:15:00Z [INFO] Retry successful
EOF

    cat << 'EOF' > /home/user/logs_raw/app_2.log
2023-10-16T08:22:10Z [CRITICAL] Out of memory killer invoked
2023-10-16T08:25:00Z [INFO] System rebooting
EOF

    # Create compressed logs
    cat << 'EOF' | gzip > /home/user/logs_raw/app_3.log.gz
2023-10-14T23:55:01Z [INFO] Nightly batch started
2023-10-14T23:58:44Z [ERROR] Missing input file dump.csv
2023-10-15T00:05:00Z [ERROR] Batch job failed
EOF

    cat << 'EOF' | gzip > /home/user/logs_raw/app_4.log.gz
2023-10-17T14:10:00Z [WARN] Disk space low
2023-10-17T15:00:00Z [CRITICAL] Disk full on /var/log
2023-10-17T15:05:00Z [INFO] Log rotation triggered
EOF

    chown -R user:user /home/user/logs_raw
    chown -R user:user /home/user/organized_logs

    chmod -R 777 /home/user
