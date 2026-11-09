#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ expect
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/proxy_routes.conf
/api/v1 10.0.0.10
/api/v2 10.0.0.11
/images 10.0.0.12
/videos 10.0.0.13
EOF

    cat << 'EOF' > /home/user/proxy_access.log
2023-10-01T10:00:00 /api/v1 5000
2023-10-01T10:01:00 /images 12000
2023-10-01T10:02:00 /api/v1 6000
2023-10-01T10:03:00 /videos 8000
2023-10-01T10:04:00 /api/v2 20000
2023-10-01T10:05:00 /api/v1 4500
2023-10-01T10:06:00 /images 3500
2023-10-01T10:07:00 /videos 9000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
