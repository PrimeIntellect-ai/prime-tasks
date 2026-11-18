#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming

    cat << 'EOF' > /home/user/incoming/app1.log
[2023-10-24 10:00:01] INFO System started
[2023-10-24 10:05:22] WARN High memory usage
[2023-10-24 10:06:01] FATAL ERROR_CODE:500 MESSAGE:Internal Server Error
[2023-10-24 10:06:05] FATAL ERROR_CODE:500 MESSAGE:Internal Server Error
[2023-10-24 10:10:00] DEBUG Cleaning up
EOF

    cat << 'EOF' > /home/user/incoming/app2.log
[2023-10-24 11:00:01] ERROR ERROR_CODE:404 MESSAGE:Not Found
[2023-10-24 11:05:22] FATAL ERROR_CODE:500 MESSAGE:Internal Server Error
[2023-10-24 11:10:01] ERROR ERROR_CODE:403 MESSAGE:Forbidden Access
EOF

    chmod -R 755 /home/user/incoming
    chmod -R 777 /home/user
