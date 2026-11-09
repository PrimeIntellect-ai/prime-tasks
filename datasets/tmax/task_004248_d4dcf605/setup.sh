#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make jq gawk coreutils grep sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_server.log
[2023-10-15 14:02:15] srcIP=10.0.0.1 method=POST endpoint=/api/v2/users latency_ms=120
[2023-10-15 14:04:59] srcIP=10.0.0.2 method=POST endpoint=/api/v2/users latency_ms=130
[2023-10-15 14:07:05] srcIP=10.0.0.1 method=GET endpoint=/api/v1/status latency_ms=45
[2023-10-15 14:08:10] srcIP=10.0.0.3 method=GET endpoint=/api/v4/admin latency_ms=200
[2023-10-15 14:09:00] srcIP=10.0.0.4 method=POST endpoint=/api/v1/status latency_ms=55
[2023-10-15 14:11:00] srcIP=10.0.0.4 method=POST endpoint=/api/v1/status latency_ms=60
[2023-10-15 14:12:30] srcIP=10.0.0.5 method=GET endpoint=/api/v3/data_export latency_ms=400
[2023-10-15 14:14:59] srcIP=10.0.0.5 method=GET endpoint=/api/v3/data_export latency_ms=410
[2023-10-15 14:15:00] srcIP=10.0.0.5 method=GET endpoint=/api/v3/data_export latency_ms=420
[2023-10-15 14:02:30] srcIP=10.0.0.1 method=POST endpoint=/api/v2/users123 latency_ms=120
[2023-10-15 14:03:00] srcIP=10.0.0.1 method=POST endpoint=/api/v2/USERS latency_ms=120
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
