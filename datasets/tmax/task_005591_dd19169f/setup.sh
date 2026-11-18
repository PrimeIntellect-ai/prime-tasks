#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/src/app /home/user/src/lib /home/user/src/network
    echo "int main() { return 0; }" > /home/user/src/app/main.c
    echo "int add(int a, int b) { return a + b; }" > /home/user/src/lib/math.c
    echo "void connect() {}" > /home/user/src/network/socket.c
    echo "void missing() {}" > /home/user/src/app/missing.c

    cat << 'EOF' > /home/user/build.log
BEGIN_RECORD
TYPE: INFO
SRC: /home/user/src/app/main.c
DETAILS: Compilation started
END_RECORD
BEGIN_RECORD
TYPE: FATAL
SRC: /home/user/src/app/main.c
DETAILS: Core dumped during initialization
END_RECORD
BEGIN_RECORD
TYPE: WARN
SRC: /home/user/src/lib/math.c
DETAILS: Unused variable
END_RECORD
BEGIN_RECORD
TYPE: FATAL
SRC: /home/user/src/network/socket.c
DETAILS: Connection reset by peer
END_RECORD
BEGIN_RECORD
TYPE: WARN
SRC: /home/user/src/app/missing.c
DETAILS: Deprecated function
END_RECORD
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
