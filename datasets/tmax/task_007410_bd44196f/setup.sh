#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc e2fsprogs e2tools sleuthkit
    pip3 install pytest

    mkdir -p /home/user/investigation

    # Create the ext4 image
    dd if=/dev/zero of=/home/user/investigation/fs.ext4 bs=1M count=16
    mkfs.ext4 -F /home/user/investigation/fs.ext4

    # Create the core C file in a temporary location
    cat << 'EOF' > /tmp/core.c
int generate_payload(int key) {
    return key * 73 + 1337;
}
EOF

    # Copy the file into the ext4 image using e2cp (avoids needing loop mount in build)
    e2cp /tmp/core.c /home/user/investigation/fs.ext4:/core.c

    # Delete the file using debugfs to simulate a deleted file where the inode still exists
    debugfs -w -R "rm core.c" /home/user/investigation/fs.ext4

    # Clean up temp file
    rm /tmp/core.c

    # Create the build.log
    cat << 'EOF' > /home/user/investigation/build.log
[INFO] Starting malicious container build...
[INFO] Preparing filesystem layers...
[INFO] Running malware_runner.py...
Traceback (most recent call last):
  File "malware_runner.py", line 14, in <module>
    payload = lib.generate_payload(key)
ctypes.ArgumentError: argument 1: <class 'TypeError'>: wrong type
[ERROR] Build crashed! Environment at time of crash:
USER=root
SECRET_KEY=99281
PATH=/usr/bin:/bin
EOF

    # Create malware_runner.py with the bug
    cat << 'EOF' > /home/user/investigation/malware_runner.py
import ctypes
import os
import subprocess

# Compile the C code into a shared library
subprocess.run(['gcc', '-shared', '-fPIC', '-o', 'libcore.so', 'core.c'], check=True)

lib = ctypes.CDLL('./libcore.so')
lib.generate_payload.argtypes = [ctypes.c_int]
lib.generate_payload.restype = ctypes.c_int

# The secret key is loaded from the environment
key = os.environ.get('SECRET_KEY', '0')

# BUG: passing a string 'key' instead of an integer to a ctypes.c_int argument
payload = lib.generate_payload(key)

print(f"PAYLOAD:{payload}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
