#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.log
1 u1 CONNECT
2 u2 CONNECT
3 u3 AUTH
4 u1 AUTH
5 u2 AUTH
6 u4 CONNECT
7 u1 REQUEST
8 u2 REQUEST
9 u1 DISCONNECT
10 u4 DISCONNECT
11 u2 CONNECT
12 u5 CONNECT
13 u5 AUTH
14 u5 REQUEST
15 u5 DISCONNECT
EOF

    cat << 'EOF' > /home/user/historical.txt
u0
u1
u8
EOF

    chmod -R 777 /home/user
