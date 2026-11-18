#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential gzip
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH=/opt/rust/bin:$PATH

    mkdir -p /home/user/logs
    mkdir -p /home/user/data

    touch /home/user/data/file1.bin
    touch /home/user/data/file2.bin
    touch /home/user/data/file3.bin
    touch /home/user/data/file4.bin

    cat << 'EOF' > /home/user/logs/log1.txt
[2023-10-01T12:00:00Z] ERROR: Write failed
  Caused by: DiskQuotaExceeded
  File: /home/user/data/file1.bin
  Size: 1024MB
[2023-10-01T12:05:00Z] ERROR: Network failed
  Caused by: Timeout
  File: /home/user/data/file2.bin
EOF

    cat << 'EOF' > /home/user/logs/log2.txt
[2023-10-02T10:00:00Z] ERROR: Write failed
  Caused by: DiskQuotaExceeded
  File: /home/user/data/file3.bin
  Size: 2048MB
EOF

    gzip /home/user/logs/log1.txt
    gzip /home/user/logs/log2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /opt/rust
    chmod -R 777 /home/user
