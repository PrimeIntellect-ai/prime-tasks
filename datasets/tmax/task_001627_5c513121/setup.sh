#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_audit.csv
Timestamp,Author,ConfigValue
2023-10-01T12:00:00Z,Alice,"Changed database IP from 192.168.1.100 to 10.0.0.5"
2023-10-01T12:05:00Z,Bob,"Updated firewall rules:
- Block 172.16.254.1
- Allow 8.8.8.8
Ensure these are applied."
2023-10-01T12:10:00Z,Charlie,"Simple config change"
2023-10-01T12:15:00Z,Dave,"Added a literal quote "" inside the config for server 10.10.10.10"
EOF

    cat << 'EOF' > /home/user/expected_clean_audit.csv
Timestamp,Author,ConfigValue
2023-10-01T12:00:00Z,Alice,"Changed database IP from [REDACTED] to [REDACTED]"
2023-10-01T12:05:00Z,Bob,"Updated firewall rules:
- Block [REDACTED]
- Allow [REDACTED]
Ensure these are applied."
2023-10-01T12:10:00Z,Charlie,"Simple config change"
2023-10-01T12:15:00Z,Dave,"Added a literal quote "" inside the config for server [REDACTED]"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
