#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs

    cat << 'EOF' > /home/user/raw_logs/run_A.json
{"run_id": "run_A", "metrics": {"loss": 0.55, "accuracy": 0.78, "epoch_time": 10.1, "mem_usage": 2048, "cpu_load": 60.5}}
EOF

    cat << 'EOF' > /home/user/raw_logs/run_B.json
{"run_id": "run_B", "metrics": {"loss": 0.45, "accuracy": 0.85, "epoch_time": 12.5, "mem_usage": 1024, "cpu_load": 45.2}}
EOF

    cat << 'EOF' > /home/user/raw_logs/run_C.json
{"run_id": "run_C", "metrics": {"loss": 0.30, "accuracy": 0.91, "epoch_time": 15.2, "mem_usage": 4096, "cpu_load": 85.1}}
EOF

    cat << 'EOF' > /home/user/raw_logs/run_D.json
{"run_id": "run_D", "metrics": {"loss": 0.60, "accuracy": 0.72, "epoch_time": 8.5, "mem_usage": 512, "cpu_load": 30.0}}
EOF

    cat << 'EOF' > /home/user/raw_logs/run_E.json
{"run_id": "run_E", "metrics": {"loss": 0.25, "accuracy": 0.94, "epoch_time": 18.0, "mem_usage": 8192, "cpu_load": 95.5}}
EOF

    chown -R user:user /home/user/raw_logs
    chmod -R 777 /home/user
