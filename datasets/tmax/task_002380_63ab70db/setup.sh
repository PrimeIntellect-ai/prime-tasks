#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/app

cat << 'EOF' > /home/user/app/crash_dump.log
[FATAL] Container unexpectedly terminated.
[INFO] Dumping environment context:
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOSTNAME=c7a8f9b1d2e3
INITIAL_STATE=8472
PYTHONUNBUFFERED=1
[ERROR] Traceback (most recent call last):
  File "malware.py", line 18, in <module>
    main()
  File "malware.py", line 14, in main
    raise RuntimeError("Segmentation fault (core dumped)")
RuntimeError: Segmentation fault (core dumped)
EOF

cat << 'EOF' > /home/user/app/malware.py
import os
import sys

def obfuscated_logic(val):
    state = val
    for i in range(50):
        if i % 2 == 0:
            state = (state * 3) % 99991
        else:
            state = (state + 17) % 99991
    return state

def main():
    seed = int(os.environ.get("INITIAL_STATE", "0"))
    target = obfuscated_logic(seed)
    print("Connecting to C2 with payload:", target)
    raise RuntimeError("Segmentation fault (core dumped)")

if __name__ == "__main__":
    main()
EOF

python3 -c "import py_compile; py_compile.compile('/home/user/app/malware.py', cfile='/home/user/app/malware.pyc')"
rm /home/user/app/malware.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
