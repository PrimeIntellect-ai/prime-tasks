#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile
import time

def create_log(filename, debug_count, info_count):
    debug_line = "[DEBUG] This is a standard length log message for testing.\n" # 59 bytes
    info_line  = "[INFO]  This is a standard length log message for testing.\n" # 59 bytes

    with open(filename, 'w') as f:
        for _ in range(debug_count):
            f.write(debug_line)
        for _ in range(info_count):
            f.write(info_line)

    return len(debug_line) * debug_count # Bytes that will be saved

def pack_nested(log_filename, tar_filename, zip_filename, mtime_offset_days):
    # Create tar.gz
    with tarfile.open(tar_filename, "w:gz") as tar:
        tar.add(log_filename, arcname=os.path.basename(log_filename))

    # Create zip
    with zipfile.ZipFile(zip_filename, 'w') as zf:
        zf.write(tar_filename, arcname=os.path.basename(tar_filename))

    # Modify zip mtime
    current_time = time.time()
    target_time = current_time - (mtime_offset_days * 86400)
    os.utime(zip_filename, (target_time, target_time))

    # Clean up intermediate files
    os.remove(log_filename)
    os.remove(tar_filename)

def setup():
    base_dir = "/home/user/storage_pool"
    os.makedirs(base_dir, exist_ok=True)
    os.makedirs(os.path.join(base_dir, "cluster_a"), exist_ok=True)
    os.makedirs(os.path.join(base_dir, "cluster_b"), exist_ok=True)

    total_saved = 0

    # Target 1: > 30 days old
    log1 = os.path.join(base_dir, "cluster_a", "sys_node1.log")
    saved1 = create_log(log1, 4000, 1000) # 4000 * 59 = 236000 bytes
    total_saved += saved1
    pack_nested(
        log1, 
        os.path.join(base_dir, "cluster_a", "sys_node1.tar.gz"), 
        os.path.join(base_dir, "cluster_a", "archive_node1.zip"), 
        45 # 45 days old (TARGET)
    )

    # Target 2: > 30 days old
    log2 = os.path.join(base_dir, "cluster_b", "sys_node2.log")
    saved2 = create_log(log2, 6500, 2000) # 6500 * 59 = 383500 bytes
    total_saved += saved2
    pack_nested(
        log2, 
        os.path.join(base_dir, "cluster_b", "sys_node2.tar.gz"), 
        os.path.join(base_dir, "cluster_b", "archive_node2.zip"), 
        60 # 60 days old (TARGET)
    )

    # Decoy: < 30 days old
    log3 = os.path.join(base_dir, "cluster_a", "sys_node3.log")
    create_log(log3, 10000, 5000)
    pack_nested(
        log3, 
        os.path.join(base_dir, "cluster_a", "sys_node3.tar.gz"), 
        os.path.join(base_dir, "cluster_a", "archive_node3.zip"), 
        10 # 10 days old (DECOY)
    )

    # Write expected truth to a hidden file for test suite (optional)
    with open("/tmp/expected_saved.txt", "w") as f:
        f.write(str(total_saved))

if __name__ == "__main__":
    setup()
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
