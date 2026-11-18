#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/bin /app/incoming /app/logs /app/staging

    # Create the mock packer binary
    cat << 'EOF' > /app/bin/packer
#!/usr/bin/env python3
import sys, os

if len(sys.argv) != 3:
    print("Usage: packer <source_dir> <output_file>")
    sys.exit(1)

source_dir = sys.argv[1]
output_file = sys.argv[2]

def pack(path, out_f, depth=0):
    if depth > 1000:
        return
    if os.path.islink(path):
        # Simulate bloat for symlinks
        out_f.write(b'0' * 500000)
        target = os.readlink(path)
        target_path = os.path.join(os.path.dirname(path), target)
        pack(target_path, out_f, depth+1)
        return
    if os.path.isdir(path):
        try:
            entries = sorted(os.listdir(path))
        except:
            return
        for entry in entries:
            pack(os.path.join(path, entry), out_f, depth+1)
    elif os.path.isfile(path):
        try:
            size = os.path.getsize(path)
            header = f"{os.path.basename(path)[:32].ljust(32)}{str(size).ljust(32)}"
            out_f.write(header.encode('utf-8'))
            with open(path, 'rb') as in_f:
                out_f.write(in_f.read())
        except:
            pass

with open(output_file, 'wb') as f:
    pack(source_dir, f)
EOF
    chmod +x /app/bin/packer

    # Create the raw artifacts
    mkdir -p /tmp/raw_artifacts
    dd if=/dev/urandom of=/tmp/raw_artifacts/clean_bin_1.elf bs=1M count=2
    dd if=/dev/urandom of=/tmp/raw_artifacts/clean_bin_2.elf bs=1M count=1
    dd if=/dev/urandom of=/tmp/raw_artifacts/vuln_bin_1.elf bs=1M count=15
    dd if=/dev/urandom of=/tmp/raw_artifacts/dep_bin_1.elf bs=1M count=10
    ln -s loop_B /tmp/raw_artifacts/loop_A
    ln -s loop_A /tmp/raw_artifacts/loop_B
    ln -s /etc/passwd /tmp/raw_artifacts/external_link

    cd /tmp/raw_artifacts
    tar -czf /app/incoming/raw_artifacts.tar.gz *
    cd /
    rm -rf /tmp/raw_artifacts

    # Create audit log
    cat << 'EOF' > /app/logs/audit.log
BEGIN RECORD
ID: 101
Filename: vuln_bin_1.elf
Status: VULNERABLE
END RECORD
BEGIN RECORD
ID: 102
Filename: clean_bin_1.elf
Status: SECURE
END RECORD
BEGIN RECORD
ID: 103
Filename: dep_bin_1.elf
Status: DEPRECATED
END RECORD
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
