#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw_logs.txt
[2023-10-01T12:00:00Z] [INFO] Processed request in 120.5ms with 0 retries.
[2023-10-01T12:00:01Z] [ERROR] Processed request in 450.2ms with 3 retries.
[2023-10-01T12:00:02Z] [WARN] Processed request in 320.0ms with 1 retries.
[2023-10-01T12:00:03Z] [INFO] Processed request in 85.4ms with 0 retries.
[2023-10-01T12:00:04Z] [ERROR] Processed request in 600.5ms with 2 retries.
[2023-10-01T12:00:05Z] [INFO] Processed request in 110.0ms with 0 retries.
[2023-10-01T12:00:06Z] [CRITICAL] Processed request in 1200.0ms with 5 retries.
[2023-10-01T12:00:07Z] [WARN] Processed request in 250.5ms with 1 retries.
[2023-10-01T12:00:08Z] [INFO] Processed request in 95.0ms with 0 retries.
[2023-10-01T12:00:09Z] [ERROR] Processed request in 550.0ms with 2 retries.
[2023-10-01T12:00:10Z] [INFO] Database backup completed successfully.
[2023-10-01T12:00:11Z] [INFO] Processed request in 105.2ms with 0 retries.
[2023-10-01T12:00:12Z] [ERROR] Processed request in 480.0ms with 3 retries.
[2023-10-01T12:00:13Z] [WARN] Processed request in 310.5ms with 1 retries.
[2023-10-01T12:00:14Z] [INFO] Processed request in 90.1ms with 0 retries.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
