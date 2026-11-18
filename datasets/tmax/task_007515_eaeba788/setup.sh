#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/incident_logs

    cat << 'EOF' > /home/user/incident_logs/app_trace.log
[INFO] User logged in. SESSION_TOKEN=A1b2C3d4E5f6G7h8
[DEBUG] Connecting to DB. PASSWORD=SuperSecret123!
[INFO] Action executed by SESSION_TOKEN=X8y7Z6w5V4u3T2s1
[ERROR] Failed auth. PASSWORD=WrongPass
[INFO] Normal log entry without sensitive data.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
