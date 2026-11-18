#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq unzip zip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/incoming
    cd /home/user/incoming

    # Valid artifact 1 (tar.gz)
    mkdir -p build1
    cat << 'EOF' > build1/metadata.json
{"name": "alpha-tool", "version": "1.0.0", "type": "binary", "status": "release"}
EOF
    echo "fake binary data" > build1/alpha.bin
    tar -czf alpha-tool.tar.gz -C build1 metadata.json alpha.bin
    rm -rf build1

    # Valid artifact 2 (zip)
    mkdir -p build2
    cat << 'EOF' > build2/metadata.json
{"name": "beta-tool", "version": "2.1.0", "type": "binary", "status": "release"}
EOF
    echo "fake binary data 2" > build2/beta.bin
    cd build2 && zip -q ../beta-tool.zip metadata.json beta.bin && cd ..
    rm -rf build2

    # Invalid artifact 1 - Wrong type (tar.gz)
    mkdir -p build3
    cat << 'EOF' > build3/metadata.json
{"name": "gamma-source", "version": "1.0.0", "type": "source", "status": "release"}
EOF
    echo "source code" > build3/main.c
    tar -czf gamma-source.tar.gz -C build3 metadata.json main.c
    rm -rf build3

    # Invalid artifact 2 - Wrong status (zip)
    mkdir -p build4
    cat << 'EOF' > build4/metadata.json
{"name": "delta-tool", "version": "0.9.0", "type": "binary", "status": "beta"}
EOF
    echo "unstable binary" > build4/delta.bin
    cd build4 && zip -q ../delta-tool.zip metadata.json delta.bin && cd ..
    rm -rf build4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
