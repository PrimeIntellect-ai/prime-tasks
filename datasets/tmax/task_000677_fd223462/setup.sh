#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/requests.txt
REQ001|3 4 +|7|210
REQ002|10 5 - 2 *|10|185
REQ003|5 5 +|10|100
REQ004|20 2 * 10 -|30|12
REQ005|7 8 *|56|215
EOF

    chmod -R 777 /home/user
