#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/server_logs.txt
TIMESTAMP=2023-10-14T08:15:01Z | MSG: Request processed. [latency: 120ms] | USER: ALICE
TIMESTAMP=2023-10-14T08:45:00Z | MSG: Request processed. [latency: 130ms] | USER: BOB
TIMESTAMP=2023-10-14T09:05:00Z | MSG: Request processed. [latency: 200ms] | USER: CHARLIE
TIMESTAMP=2023-10-14T09:15:00Z | MSG: Request processed. [latency: 210ms] | USER: ALICE
TIMESTAMP=2023-10-14T10:00:00Z | MSG: Request processed. [latency: 50ms] | USER: BOB
TIMESTAMP=2023-10-14T10:30:00Z | MSG: Request processed. [latency: 60ms] | USER: ALICE
TIMESTAMP=2023-10-14T23:59:59Z | MSG: Request processed. [latency: 999ms] | USER: SYSTEM
EOF

    chmod -R 777 /home/user
