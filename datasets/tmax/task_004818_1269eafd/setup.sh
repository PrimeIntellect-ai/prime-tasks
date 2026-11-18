#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifact_repo/groupA
    mkdir -p /home/user/artifact_repo/groupB

    cat << 'EOF' > /home/user/repo_config.ini
[Paths]
OldPrefix=C:\OldSystem\Binaries\
NewPrefix=/opt/new_system/artifacts/
EOF

    cat << 'EOF' > /tmp/artifact1.txt
Version=1.0.4
Path=C:\OldSystem\Binaries\groupA\artifact1.bin
Checksum=abcdef
EOF

    cat << 'EOF' > /tmp/artifact2.txt
Version=2.1.0
Path=C:\OldSystem\Binaries\groupB\artifact2.bin
Checksum=123456
EOF

    iconv -f UTF-8 -t UTF-16LE /tmp/artifact1.txt > /home/user/artifact_repo/groupA/artifact1.meta
    iconv -f UTF-8 -t UTF-16LE /tmp/artifact2.txt > /home/user/artifact_repo/groupB/artifact2.meta

    rm /tmp/artifact1.txt /tmp/artifact2.txt

    chmod -R 777 /home/user
