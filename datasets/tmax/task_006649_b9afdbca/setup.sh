#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/lib_versions.txt
libc.so - 2.31.0
libpthread.so - 2.31.0
libmath_custom.so - 2.3.9
libcrypto.so - 1.1.1
EOF

    cat << 'EOF' > /home/user/valgrind_mock.log
[INFO] Starting mock execution
[WARN] LEAK: 2048 bytes at 0x0001
[INFO] allocating buffer
[WARN] LEAK: 4096 bytes at 0x0002
[INFO] Freeing memory
[WARN] LEAK: 128 bytes at 0x0003
[INFO] Execution finished
EOF

    chmod 644 /home/user/lib_versions.txt
    chmod 644 /home/user/valgrind_mock.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
