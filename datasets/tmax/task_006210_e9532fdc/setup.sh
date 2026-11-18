#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/tests

    cat << 'EOF' > /home/user/tests/test1.sm
PUSH 10
PUSH 20
ADD
PRINT
EOF

    cat << 'EOF' > /home/user/tests/test2.sm
PUSH 5
PUSH 15
SUB
PRINT
EOF

    cat << 'EOF' > /home/user/tests/test3.sm
PUSH 100
PUSH 50
ADD
PUSH 10
SUB
PRINT
EOF

    cat << 'EOF' > /home/user/tests/test4.sm
PUSH 5
ADD
PRINT
EOF

    cat << 'EOF' > /home/user/expected_output.txt
-10
ERROR
30
140
EOF

    chmod -R 777 /home/user
