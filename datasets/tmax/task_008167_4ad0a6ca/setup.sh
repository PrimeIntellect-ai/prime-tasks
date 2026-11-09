#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/doc_events.wal
HEADER|101|0|47
Hello, this is the start of the documentation.
HEADER|202|0|26
Chapter 1: Initial Setup.
HEADER|101|1|38
It describes the system architecture.
HEADER|202|1|32
Run the configure script first.
EOF

    chmod 644 /home/user/doc_events.wal
    chmod -R 777 /home/user
