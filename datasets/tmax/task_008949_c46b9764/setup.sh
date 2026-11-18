#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_metrics.log
[2023-10-01 10:03:12] INFO Server started. METRIC_VAL: 42.5
[2023-10-01 10:12:01] DEBUG Checking connections.
[2023-10-01 10:14:30] WARN Minor spike. METRIC_VAL: 43.5
[2023-10-01 10:18:05] WARN High load detected. CPU_VAL: 99.0 METRIC_VAL: 55.2
[2023-10-01 10:25:00] INFO Still high load. METRIC_VAL: 56.8
[2023-10-01 11:02:11] ERROR Connection timeout. METRIC_VAL: 48.0
[2023-10-01 11:47:33] INFO Normal operations. METRIC_VAL: 30.1
EOF

    chmod -R 777 /home/user
