#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming/projA/mac
    mkdir -p /home/user/incoming/projB/win
    mkdir -p /home/user/incoming/shared/linux

    echo -n "dummy mac file" > /home/user/incoming/projA/mac/release.zip
    echo -n "dummy win file" > /home/user/incoming/projB/win/binary.exe
    echo -n "dummy linux file" > /home/user/incoming/shared/linux/app.tar.gz

    cat << 'EOF' > /home/user/incoming/metadata.csv
projA/mac/release.zip,macos,1.0.0
projB/win/binary.exe,windows,2.1.0
shared/linux/app.tar.gz,linux,3.0.1
EOF

    chmod -R 777 /home/user
