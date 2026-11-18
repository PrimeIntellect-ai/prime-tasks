#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    mkdir -p /home/user/raw_artifacts
    mkdir -p /app

    # Generate base files
    dd if=/dev/urandom of=/tmp/base1.bin bs=1M count=1 2>/dev/null
    dd if=/dev/urandom of=/tmp/base2.bin bs=500K count=1 2>/dev/null
    base64 /dev/urandom | head -c 200000 > /tmp/base3.meta.txt

    # Create duplicates
    for i in 1 2 3 4 5; do
        cp /tmp/base1.bin "/home/user/raw_artifacts/file_A_${i}.bin"
        cp /tmp/base2.bin "/home/user/raw_artifacts/file_B_${i}.bin"
        cp /tmp/base3.meta.txt "/home/user/raw_artifacts/meta_C_${i}.meta.txt"
        cp /tmp/base3.meta.txt "/home/user/raw_artifacts/doc_D_${i}.doc"
    done

    # Create artifact_packer
    cat << 'EOF' > /app/artifact_packer
#!/usr/bin/env python3
import sys
import os

if len(sys.argv) != 3:
    print("Usage: artifact_packer <src_dir> <out_file>")
    sys.exit(1)

src_dir = sys.argv[1]
out_file = sys.argv[2]

seen_inodes = set()

with open(out_file, 'wb') as out:
    for root, dirs, files in os.walk(src_dir):
        for f in sorted(files):
            path = os.path.join(root, f)
            try:
                st = os.stat(path)
                if st.st_ino in seen_inodes:
                    out.write(b'\x00\x00\x00\x00')
                else:
                    seen_inodes.add(st.st_ino)
                    with open(path, 'rb') as f_in:
                        out.write(f_in.read())
            except Exception as e:
                pass
EOF
    chmod +x /app/artifact_packer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
