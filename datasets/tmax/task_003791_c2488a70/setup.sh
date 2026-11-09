#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar gzip sed gawk
    pip3 install pytest

    mkdir -p /home/user/legacy_docs
    echo "Welcome to AcmeCorp.    This is v1.0 of our software." > /home/user/legacy_docs/readme.txt
    echo "AcmeCorp v1.0 architecture:  Client ->   Server." > /home/user/legacy_docs/arch.md
    echo "     Indent test for AcmeCorp v1.0." > /home/user/legacy_docs/notes.txt

    tar -czf /home/user/legacy_docs.tar.gz -C /home/user legacy_docs
    rm -rf /home/user/legacy_docs

    cat << 'EOF' > /home/user/build.conf
REPLACE:AcmeCorp:NovaTech
REPLACE:v1.0:v2.2
COMPRESS_EXT:.txt
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
