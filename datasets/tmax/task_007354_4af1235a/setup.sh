#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        curl \
        build-essential \
        zip \
        unzip \
        tar \
        libc-bin

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Install Rust for the user
    su - user -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

    mkdir -p /home/user/artifact_manager/binaries
    mkdir -p /home/user/artifact_manager/curated

    # Create mock artifacts
    mkdir -p /tmp/b1 /tmp/b2 /tmp/b3

    echo "binary_data_A" > /tmp/b1/fileA.bin
    echo "binary_data_B" > /tmp/b1/fileB.bin
    cd /tmp/b1 && zip -q inner1.zip fileA.bin fileB.bin
    cd /tmp/b1 && tar -czf /home/user/artifact_manager/binaries/bundle_1.tar.gz inner1.zip

    echo "binary_data_C" > /tmp/b2/fileC.bin
    cd /tmp/b2 && zip -q inner2.zip fileC.bin
    cd /tmp/b2 && tar -czf /home/user/artifact_manager/binaries/bundle_2.tar.gz inner2.zip

    echo "binary_data_D" > /tmp/b3/fileD.bin
    cd /tmp/b3 && zip -q inner3.zip fileD.bin
    cd /tmp/b3 && tar -czf /home/user/artifact_manager/binaries/bundle_3.tar.gz inner3.zip

    # Create log file in ISO-8859-1
    cat << 'EOF' > /tmp/uploads_utf8.log
START_RECORD
File: /home/user/artifact_manager/binaries/bundle_1.tar.gz
Status: SUCCESS
END_RECORD
START_RECORD
File: /home/user/artifact_manager/binaries/bundle_2.tar.gz
Status: FAILED
END_RECORD
START_RECORD
File: /home/user/artifact_manager/binaries/bundle_3.tar.gz
Status: SUCCESS
END_RECORD
EOF

    iconv -f UTF-8 -t ISO-8859-1 /tmp/uploads_utf8.log > /home/user/artifact_manager/uploads.log

    chmod -R 777 /home/user
