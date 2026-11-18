#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/requests.txt
1000 SGVsbG8=
1000 V29ybGQ=
1000 RXhjZWVkZWRMaW1pdA==
1001 SW52YWxpZEBiYXNlNjQ=
1001 TmV4dFNlYw==
1001 R29vZA==
1002 U2tpcHBlZA==
1002 QW5vdGhlcg==
1002 ZmFpbHM=
EOF

    chmod -R 777 /home/user
