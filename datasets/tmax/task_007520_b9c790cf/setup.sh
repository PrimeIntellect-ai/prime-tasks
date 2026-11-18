#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/repo

    # Create raw binaries
    touch /home/user/incoming/raw_001.dat
    touch /home/user/incoming/raw_002.dat
    touch /home/user/incoming/raw_003.dat

    # Create the manifest
    cat << 'EOF' > /home/user/incoming/manifest.log
[Artifact]
File: raw_001.dat
Arch: x86_64
Target: bin/app_main.bin
Status: verified

[Artifact]
File: raw_002.dat
Arch: armv7
Target: lib/helper.so
Status: corrupted

[Artifact]
File: raw_003.dat
Arch: aarch64
Target: modules/network.ko
Status: verified
EOF

    # Create the trigger
    touch /home/user/incoming/process.trigger

    chmod -R 777 /home/user
