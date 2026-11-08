#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Create the user first to ensure /home/user exists
useradd -m -s /bin/bash user || true

# Generate the initial state using Python
cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import random
import struct

os.makedirs("/home/user/raw_setup/bin", exist_ok=True)
log_lines = []

random.seed(42)

for i in range(1, 101):
    is_valid = random.choice([True, False])
    expected_magic = random.randint(0x10000000, 0xFFFFFFFF)

    file_path = f"bin/artifact_{i}.bin"
    full_path = f"/home/user/raw_setup/{file_path}"

    # Write binary
    actual_magic = expected_magic if is_valid else random.randint(0x10000000, 0xFFFFFFFF)
    with open(full_path, "wb") as f:
        f.write(struct.pack(">I", actual_magic))
        # Add some random padding
        f.write(os.urandom(64))

    # Create log record
    log_lines.append("[Record Start]")
    log_lines.append(f"Artifact ID: {i}")
    log_lines.append(f"File: {file_path}")
    log_lines.append(f"Expected Magic: 0x{expected_magic:08X}")
    log_lines.append("Status: UNVERIFIED")

with open("/home/user/raw_setup/artifact_registry.log", "w") as f:
    f.write("\n".join(log_lines) + "\n")

with tarfile.open("/home/user/raw_artifacts.tar.gz", "w:gz") as tar:
    tar.add("/home/user/raw_setup/artifact_registry.log", arcname="artifact_registry.log")
    tar.add("/home/user/raw_setup/bin", arcname="bin")

os.system("rm -rf /home/user/raw_setup")
EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
