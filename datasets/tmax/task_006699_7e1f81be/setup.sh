#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/upload_requests.log
2023-10-27T10:00:01 192.168.1.100 dXBsb2Fkcy9pbWFnZTEucG5n
2023-10-27T10:05:22 192.168.1.101 dXBsb2Fkcy9kb2N1bWVudC5wZGY=
2023-10-27T10:12:45 10.0.0.5 dXBsb2Fkcy8uLi8uLi8uLi9ldGMvcGFzc3dk
2023-10-27T10:15:00 192.168.1.102 dXBsb2Fkcy9hdmF0YXIuanBn
EOF

    chmod -R 777 /home/user
