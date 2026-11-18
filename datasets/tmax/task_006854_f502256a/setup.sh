#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest requests

    # Create directories
    mkdir -p /home/user/server
    mkdir -p /home/user/workspace

    # Create the log file
    cat << 'EOF' > /home/user/server/logs.txt
[INFO] 2023-10-01 10:00:00 - UserID: A1 - Request: /api/v1/data - Duration: 12ms - Status: 200
[WARN] 2023-10-01 10:00:05 - UserID: B2 - Request: /api/v1/data - Duration: N/Ams - Status: 500
[INFO] 2023-10-01 10:00:10 - UserID: C3 - Request: /api/v1/data - Duration: 25ms - Status: 200
[INFO] 2023-10-01 10:00:15 - UserID: A1 - Request: /api/v1/data - Duration: 35ms - Status: 200
[ERROR] 2023-10-01 10:00:20 - UserID: D4 - Request: /api/v1/data - Duration: errorms - Status: 400
[INFO] 2023-10-01 10:00:25 - UserID: B2 - Request: /api/v1/data - Duration: 8ms - Status: 200
[INFO] 2023-10-01 10:00:30 - UserID: C3 - Request: /api/v1/data - Duration: 14ms - Status: 200
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
