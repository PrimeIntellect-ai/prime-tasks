#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import hashlib

base_dir = "/home/user/artifact_dump"
os.makedirs(os.path.join(base_dir, "dir1", "dir2"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "dir3"), exist_ok=True)

def make_bin(path, version, data):
    content = version.ljust(16, '-').encode('ascii') + data
    with open(path, 'wb') as f:
        f.write(content)
    return hashlib.sha256(content).hexdigest()

# Create binary files
hash_a = make_bin(os.path.join(base_dir, "a.bin"), "VER:1.0.0", b"random_data_A_12345")
hash_b = make_bin(os.path.join(base_dir, "dir1", "b.bin"), "VER:2.1.0", b"random_data_B_67890")
hash_c = make_bin(os.path.join(base_dir, "dir1", "dir2", "c.bin"), "VER:1.5.5", b"random_data_C_corrupt")
hash_d = make_bin(os.path.join(base_dir, "dir3", "d.bin"), "VER:3.0.0", b"random_data_D_99999")

# Create symlink bombs
os.symlink("../dir3", os.path.join(base_dir, "dir1", "loop_to_3"))
os.symlink("../dir1", os.path.join(base_dir, "dir3", "loop_to_1"))
os.symlink(".", os.path.join(base_dir, "self_loop"))
os.symlink("dir1/b.bin", os.path.join(base_dir, "link_to_b.bin"))

# Create security logs
log_content = f"""[INFO] System startup
[DEBUG] Checking file integrity
[ERROR] Corrupt file detected - BLACKLIST_HASH: {hash_c}
[INFO] Scan complete
[DEBUG] Another line of text
[ERROR] Corrupt file detected - BLACKLIST_HASH: fakehash1234567890abcdef
"""
with open("/home/user/security_logs.txt", "w") as f:
    f.write(log_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
