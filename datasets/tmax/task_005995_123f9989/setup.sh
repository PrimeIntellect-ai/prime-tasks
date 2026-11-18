#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_logs.txt
[2023-10-24 10:00:01] [10.0.0.1] [200] [OK]
[2023-10-24 10:00:02] [10.0.0.2] [200] [OK]
[2023-10-24 10:00:03] [10.0.0.3] [403] [Forbidden]
[2023-10-24 10:00:04] [10.0.0.4] [500] [Internal Server Error]
[2023-10-24 10:00:05] [10.0.0.5] [200] [OK]
[2023-10-24 10:00:06] [10.0.0.6] [200] [OK]
[2023-10-24 10:00:07] [10.0.0.7] [404] [Not Found]
[2023-10-24 10:00:08] [10.0.0.8] [502] [Bad Gateway]
[2023-10-24 10:00:09] [10.0.0.9] [200] [OK]
[2023-10-24 10:00:10] [10.0.0.10] [200] [OK]
[2023-10-24 10:00:11] [10.0.0.11] [400] [Bad Request]
[2023-10-24 10:00:12] [10.0.0.12] [401] [Unauthorized]
[2023-10-24 10:00:13] [10.0.0.13] [503] [Service Unavailable]
[2023-10-24 10:00:14] [10.0.0.14] [500] [Internal Server Error]
[2023-10-24 10:00:15] [10.0.0.15] [404] [Not Found]
[2023-10-24 10:00:16] [10.0.0.16] [504] [Gateway Timeout]
[2023-10-24 10:00:17] [10.0.0.17] [200] [OK]
[2023-10-24 10:00:18] [10.0.0.18] [403] [Forbidden]
[2023-10-24 10:00:19] [10.0.0.19] [500] [Internal Server Error]
EOF

    chmod -R 777 /home/user
