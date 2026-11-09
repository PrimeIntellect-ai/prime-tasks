#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts_raw/group1
    mkdir -p /home/user/artifacts_raw/group2/nested

    # Artifact 1
    mkdir -p /tmp/art1
    cat << 'EOF' > /tmp/art1/meta.ini
[Artifact]
id=art_001
payload_file=data1.bin
EOF
    echo -n -e '\x01\x02\x03\x04\x0A\x0B\x0C' > /tmp/art1/data1.bin
    tar -czf /home/user/artifacts_raw/group1/bundleA.tar.gz -C /tmp/art1 meta.ini data1.bin

    # Artifact 2
    mkdir -p /tmp/art2
    cat << 'EOF' > /tmp/art2/meta.ini
[Artifact]
id=omega_42
payload_file=payload.dat
EOF
    echo -n -e '\xFF\xEE\xDD\xCC\xBB\xAA' > /tmp/art2/payload.dat
    tar -czf /home/user/artifacts_raw/group2/bundleB.tar.gz -C /tmp/art2 meta.ini payload.dat

    # Artifact 3
    mkdir -p /tmp/art3
    cat << 'EOF' > /tmp/art3/meta.ini
[Artifact]
id=zeta_77
payload_file=core.dump
EOF
    echo -n -e '\x00\x00\x00\x00\x42\x42' > /tmp/art3/core.dump
    tar -czf /home/user/artifacts_raw/group2/nested/bundleC.tar.gz -C /tmp/art3 meta.ini core.dump

    rm -rf /tmp/art1 /tmp/art2 /tmp/art3

    chmod -R 777 /home/user
