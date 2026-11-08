#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_logs/service_a
    mkdir -p /home/user/project_logs/service_b/nested
    mkdir -p /home/user/project_logs/service_c

    cat << 'EOF' > /home/user/project_logs/service_a/app.log
[2023-10-01 10:00:00] INFO Starting app
[2023-10-01 10:05:00] ERROR Missing file
[2023-10-01 10:10:00] FATAL CRITICAL_FAILURE: DB connection lost
    at db.connect()
    at main()
[2023-10-01 10:15:00] INFO Shutting down
EOF

    cat << 'EOF' > /home/user/project_logs/service_b/nested/worker.log
[2023-10-02 11:00:00] WARN Memory high
[2023-10-02 11:05:00] FATAL CRITICAL_FAILURE: Out of memory
    Heap dump:
    0x0001
    0x0002
[2023-10-02 11:06:00] INFO Restarted
EOF

    cat << 'EOF' > /home/user/project_logs/service_c/misc.log
[2023-10-03 12:00:00] INFO All good here
[2023-10-03 12:01:00] INFO Nothing to see
EOF

    cat << 'EOF' > /home/user/project_logs/service_a/other.log
[2023-10-04 13:00:00] FATAL CRITICAL_FAILURE: Network timeout
    Retries: 5
    Status: Failed
[2023-10-04 13:01:00] INFO Network recovered
EOF

    chmod -R 777 /home/user
