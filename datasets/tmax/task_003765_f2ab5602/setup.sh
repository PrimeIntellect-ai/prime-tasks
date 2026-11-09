#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_configs
    mkdir -p /home/user/quarantine
    mkdir -p /home/user/reconstructed_configs

    cat << 'EOF' > /home/user/raw_configs/config_10.json
{"max_memory": 1024, "timeout": 1.0, "log_level": "INFO", "feature_flags": {}}
EOF

    cat << 'EOF' > /home/user/raw_configs/config_20.json
{"max_memory": null, "timeout": 2.0, "log_level": null, "feature_flags": {}}
EOF

    cat << 'EOF' > /home/user/raw_configs/config_25.json
{THIS IS INVALID JSON DATA
EOF

    cat << 'EOF' > /home/user/raw_configs/config_30.json
{"max_memory": 3072, "timeout": null, "log_level": "DEBUG", "feature_flags": {}}
EOF

    cat << 'EOF' > /home/user/raw_configs/config_40.json
{"max_memory": 4096, "timeout": 4.0, "log_level": null, "feature_flags": {}}
EOF

    cat << 'EOF' > /home/user/raw_configs/config_50.json
{"max_memory": 5120, "timeout": 5.0, "log_level": "WARN", "feature_flags": {}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
