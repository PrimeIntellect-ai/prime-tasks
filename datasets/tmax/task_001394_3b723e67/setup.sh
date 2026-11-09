#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app

cat << 'EOF' > /home/user/app/processor.py
def process(ref_id):
    if ref_id == "ERR-9482-SYS":
        raise RuntimeError("System Fault")
    return True
EOF

cat << 'EOF' > /home/user/app/build.py
import sys

def run_build():
    print("Starting build...")
    # Deliberate typo to cause NameError
    prnt("Build complete")

if __name__ == "__main__":
    run_build()
EOF

dd if=/dev/urandom of=/home/user/app/memory.dmp bs=1K count=10 status=none
echo -n "CRASH_REF: ERR-9482-SYS" >> /home/user/app/memory.dmp
dd if=/dev/urandom bs=1K count=5 status=none >> /home/user/app/memory.dmp

chmod -R 777 /home/user
