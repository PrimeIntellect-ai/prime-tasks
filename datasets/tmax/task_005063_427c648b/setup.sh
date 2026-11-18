#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/services
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/services/service_alpha.json
{
  "service_name": "alpha",
  "port": 8081,
  "api_key": "EXPIRED_SYS_KEY_a8f9"
}
EOF

    cat << 'EOF' > /home/user/services/service_beta.json
{
  "service_name": "beta",
  "port": 8082,
  "api_key": "VALID_KEY_xyz1"
}
EOF

    cat << 'EOF' > /home/user/services/service_gamma.json
{
  "service_name": "gamma",
  "port": 8083,
  "api_key": "EXPIRED_SYS_KEY_a8f9"
}
EOF

    cat << 'EOF' > /home/user/logs/api_access.log
[2023-10-24 10:00:01] IP: 192.168.1.100 accessed PORT: 8081 with KEY: EXPIRED_SYS_KEY_a8f9 result: SUCCESS
[2023-10-24 10:05:22] IP: 10.5.12.44 accessed PORT: 8081 with KEY: EXPIRED_SYS_KEY_a8f9 result: SUCCESS
[2023-10-24 10:10:33] IP: 203.0.113.5 accessed PORT: 8083 with KEY: EXPIRED_SYS_KEY_a8f9 result: SUCCESS
[2023-10-24 10:15:44] IP: 198.51.100.22 accessed PORT: 8082 with KEY: VALID_KEY_xyz1 result: SUCCESS
[2023-10-24 10:20:55] IP: 45.33.22.11 accessed PORT: 8083 with KEY: EXPIRED_SYS_KEY_a8f9 result: FAILURE
[2023-10-24 10:25:00] IP: 192.168.1.100 accessed PORT: 8083 with KEY: EXPIRED_SYS_KEY_a8f9 result: SUCCESS
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
