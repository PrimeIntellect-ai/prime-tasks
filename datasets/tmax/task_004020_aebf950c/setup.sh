#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cargo \
        rustc \
        binutils \
        tar

    pip3 install pytest

    mkdir -p /home/user/incoming/raw
    mkdir -p /home/user/curator
    mkdir -p /home/user/repo/all_binaries

    # Create dummy ELF files for x86_64 and aarch64
    # x86_64
    echo -ne '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00\x01\x00\x00\x00' > /home/user/incoming/raw/server_bin
    echo -ne '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00\x01\x00\x00\x00' > /home/user/incoming/raw/worker_bin
    # aarch64
    echo -ne '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00\x01\x00\x00\x00' > /home/user/incoming/raw/client_bin
    echo -ne '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00\x01\x00\x00\x00' > /home/user/incoming/raw/proxy_bin

    cd /home/user/incoming/raw
    tar -czf /home/user/incoming/artifacts.tar.gz *
    cd /home/user
    rm -rf /home/user/incoming/raw

    cat << 'EOF' > /home/user/incoming/build.log
--- BUILD RECORD ---
Artifact: server_bin
Target: production
Version: 1.0.5
Status: SUCCESS
--------------------
--- BUILD RECORD ---
Artifact: server_bin
Target: staging
Version: 1.2.0
Status: SUCCESS
--------------------
--- BUILD RECORD ---
Artifact: client_bin
Target: production
Version: 2.1.0
Status: SUCCESS
--------------------
--- BUILD RECORD ---
Artifact: worker_bin
Target: production
Version: 0.9.5
Status: FAILED
--------------------
--- BUILD RECORD ---
Artifact: proxy_bin
Target: production
Version: 3.0.0
Status: SUCCESS
--------------------
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
