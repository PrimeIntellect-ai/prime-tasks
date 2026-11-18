#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.txt
user_id|email|score_A|score_B|text_A|text_B
101|john.doe@test.com|50|75|Good job|Needs work
102|jane@test.com|90||Excellent|
103|a@domain.org||10|Empty A|Very bad
EOF

    chmod -R 777 /home/user
