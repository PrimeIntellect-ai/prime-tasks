#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils coreutils
    pip3 install pytest

    mkdir -p /home/user/logs
    cd /home/user

    # Create service_a.log
    cat << 'EOF' > /home/user/logs/service_a.log
2023-10-24T09:15:01 INFO [Router] Started processing ReqID: 8001
2023-10-24T09:15:03 INFO [Router] Finished processing ReqID: 8001
2023-10-24T09:15:04 INFO [Router] Started processing ReqID: 8002
2023-10-24T09:15:07 INFO [Router] Started processing ReqID: 8003
2023-10-24T09:15:09 INFO [Router] Finished processing ReqID: 8002
2023-10-24T09:15:15 CRITICAL [Router] Segmentation fault (core dumped)
EOF

    # Create service_b.log
    cat << 'EOF' > /home/user/logs/service_b.log
2023-10-24T09:15:02 INFO [Processor] Handling data for ReqID: 8001
2023-10-24T09:15:05 INFO [Processor] Handling data for ReqID: 8002
2023-10-24T09:15:08 INFO [Processor] Handling data for ReqID: 8003
2023-10-24T09:15:12 INFO [Processor] Handling data for ReqID: 8004
EOF

    # Create a fake core dump with binary garbage and the required strings
    dd if=/dev/urandom of=/home/user/dump.core bs=1K count=1024 2>/dev/null
    echo "Some random memory garbage here" >> /home/user/dump.core
    echo "ReqID: 8004" >> /home/user/dump.core
    echo "Buffer allocation: 0x7ffd9b8a" >> /home/user/dump.core
    echo "PAYLOAD_X9f823mPq" >> /home/user/dump.core
    dd if=/dev/urandom bs=1K count=512 2>/dev/null >> /home/user/dump.core

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/logs /home/user/dump.core
    chmod -R 777 /home/user
