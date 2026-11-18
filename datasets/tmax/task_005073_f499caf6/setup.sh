#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/telemetry.txt
2023-10-12T08:14:05Z 45.2 OK
2023-10-12T08:29:55Z 46.1 FAIL: timeout
2023-10-12T08:45:10Z 47.0 OK
2023-10-12T09:05:00Z 42.5 FAIL: disconnect
2023-10-12T09:15:22Z 43.0 OK
2023-10-12T09:45:00Z 40.5 FAIL: sensor
2023-10-13T10:01:00Z 10.0 OK
2023-10-13T10:59:59Z 10.0 OK
EOF

    chmod -R 777 /home/user
