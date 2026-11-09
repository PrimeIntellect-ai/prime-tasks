#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr gcc
    pip3 install pytest

    mkdir -p /app
    convert -size 400x200 xc:white -fill black -pointsize 20 -annotate +10+40 "CONFIGURATION DETAILS:\nCHUNK_PREFIX: pkg_chunk_\nMAGIC_SIG: ZSLIP_ARCHIVE_v1" /app/archive_map.png

    mkdir -p /home/user/artifacts/dir1 /home/user/artifacts/dir2/nested

    # Construct the binary file
    printf "ZSLIP_ARCHIVE_v1\n" > /tmp/full.bin
    printf "../../etc/passwd\0" >> /tmp/full.bin
    printf "valid_dir/../hidden/file.txt\0" >> /tmp/full.bin
    printf "../../../../var/log/syslog\0" >> /tmp/full.bin
    printf "normal_file.bin\0" >> /tmp/full.bin

    # Ground truth binary
    printf "etc/passwd\0" > /app/ground_truth.bin
    printf "valid_dir/hidden/file.txt\0" >> /app/ground_truth.bin
    printf "var/log/syslog\0" >> /app/ground_truth.bin
    printf "normal_file.bin\0" >> /app/ground_truth.bin

    # Split the file into chunks
    split -b 15 /tmp/full.bin /tmp/split_
    mv /tmp/split_aa /home/user/artifacts/pkg_chunk_01
    mv /tmp/split_ab /home/user/artifacts/dir2/nested/pkg_chunk_02
    mv /tmp/split_ac /home/user/artifacts/dir1/pkg_chunk_03
    mv /tmp/split_ad /home/user/artifacts/pkg_chunk_04
    mv /tmp/split_ae /home/user/artifacts/dir2/pkg_chunk_05

    # Create the Python verifier
    cat << 'EOF' > /app/verify_paths.py
import sys

def read_null_terminated(filepath):
    with open(filepath, 'rb') as f:
        content = f.read()
    return [p for p in content.split(b'\x00') if p]

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("accuracy=0.0")
        sys.exit(1)

    try:
        agent_paths = read_null_terminated(sys.argv[1])
        truth_paths = read_null_terminated(sys.argv[2])
    except Exception:
        print("accuracy=0.0")
        sys.exit(1)

    if not truth_paths:
        print("accuracy=0.0")
        sys.exit(1)

    matches = sum(1 for a, t in zip(agent_paths, truth_paths) if a == t)
    accuracy = matches / len(truth_paths)
    print(f"accuracy={accuracy}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
