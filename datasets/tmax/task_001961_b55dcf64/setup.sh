#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils tar coreutils
    pip3 install pytest

    mkdir -p /home/user/artifacts_tmp/build_alpha
    mkdir -p /home/user/artifacts_tmp/build_beta
    mkdir -p /home/user/artifacts_tmp/build_gamma

    cp /bin/ls /home/user/artifacts_tmp/build_alpha/main.elf
    cp /bin/cat /home/user/artifacts_tmp/build_beta/main.elf
    cp /bin/echo /home/user/artifacts_tmp/build_gamma/main.elf

    cat << 'EOF' > /home/user/artifacts_tmp/build_alpha/trace.log
Info: System booting
--- BEGIN CRITICAL ---
Error in module A
Stack trace: 0x1234
--- END CRITICAL ---
Warning: Low memory
--- BEGIN CRITICAL ---
Timeout reached
--- END CRITICAL ---
EOF

    cat << 'EOF' > /home/user/artifacts_tmp/build_beta/trace.log
Info: System booting
Warning: High CPU usage
EOF

    cat << 'EOF' > /home/user/artifacts_tmp/build_gamma/trace.log
Info: Connection established
--- BEGIN CRITICAL ---
Segfault at 0x0000
--- END CRITICAL ---
EOF

    cd /home/user/artifacts_tmp
    tar -czf /home/user/artifacts.tar.gz *
    cd /home/user
    rm -rf /home/user/artifacts_tmp
    mkdir -p /home/user/chunks

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
