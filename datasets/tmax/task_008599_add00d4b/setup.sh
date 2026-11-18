#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data /home/user/output

    cat << 'EOF' > /home/user/data/config_changes.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "server": "alpha", "config_val": "init", "cpu_load": 50.0}
{"timestamp": "2023-10-01T10:10:00Z", "server": "alpha", "config_val": "bad_unicode\u002", "cpu_load": null}
{"timestamp": "2023-10-01T10:20:00Z", "server": "alpha", "config_val": "update1", "cpu_load": 90.0}
{"timestamp": "2023-10-01T10:30:00Z", "server": "alpha", "config_val": "update2", "cpu_load": null}
{"timestamp": "2023-10-01T10:40:00Z", "server": "alpha", "config_val": "update3", "cpu_load": 75.0}
{"timestamp": "2023-10-01T10:05:00Z", "server": "beta", "config_val": "start", "cpu_load": null}
{"timestamp": "2023-10-01T10:15:00Z", "server": "beta", "config_val": "error\uX", "cpu_load": 85.0}
{"timestamp": "2023-10-01T10:25:00Z", "server": "beta", "config_val": "fix", "cpu_load": 85.0}
{"timestamp": "2023-10-01T10:35:00Z", "server": "beta", "config_val": "deploy", "cpu_load": 40.0}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
