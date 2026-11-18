#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/data
    cd /home/user/project

    cat << 'EOF' > build.py
import glob
import json
import sys

def main():
    data = {}
    try:
        for filepath in sorted(glob.glob("data/*.txt")):
            with open(filepath, 'r') as f:
                data[filepath] = f.read()
    except Exception as e:
        print("Build failed with an encoding error!")
        sys.exit(1)

    with open("output.json", "w") as f:
        json.dump(data, f)

if __name__ == "__main__":
    main()
EOF

    python3 -c "
import os
for i in range(1, 501):
    with open(f'/home/user/project/data/file_{i:03d}.txt', 'w') as f:
        f.write(f'Valid data for file {i}\n')
with open('/home/user/project/data/file_387.txt', 'wb') as f:
    f.write(b'Invalid \xff byte here\n')
"

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
