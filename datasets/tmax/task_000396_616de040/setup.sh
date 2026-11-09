#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc diffutils
    pip3 install pytest

    mkdir -p /home/user/qa_env

    cat << 'EOF' > /home/user/qa_env/raw_requests.txt
0x0000000F
0x00000005
0x00000001
0x0000000B
0x00000008
0x00000019
0x0000000E
0x00000014
0x0000002A
EOF

    cat << 'EOF' > /home/user/qa_env/expected_violations.log
11
14
15
20
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
