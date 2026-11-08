#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deployment.log
[2023-11-01 10:00:00] [PORT: 8081] [STATUS: IN_PROGRESS]
[2023-11-01 10:01:00] [PORT: 8081] [STATUS: SUCCESS]
[2023-11-01 10:02:00] [PORT: 8082] [STATUS: IN_PROGRESS]
[2023-11-01 10:03:00] [PORT: 8082] [STATUS: FAILED]
[2023-11-01 10:04:00] [PORT: 8083] [STATUS: IN_PROGRESS]
[2023-11-01 10:05:00] [PORT: 8083] [STATUS: SUCCESS]
[2023-11-01 10:06:00] [PORT: 8081] [STATUS: FAILED]
[2023-11-01 10:07:00] [PORT: 8084] [STATUS: SUCCESS]
[2023-11-01 10:08:00] [PORT: 8085] [STATUS: IN_PROGRESS]
[2023-11-01 10:09:00] [PORT: 8085] [STATUS: SUCCESS]
EOF

    chmod -R 777 /home/user
