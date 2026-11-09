#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_data.py
import os

os.makedirs("/home/user", exist_ok=True)

with open("/home/user/run1.txt", "w") as f1, open("/home/user/run2.txt", "w") as f2:
    for i in range(100):
        # run 1 is just i
        f1.write(f"{float(i)}\n")

        # run 2 is i + 0.5 for even i, i - 0.1 for odd i
        if i % 2 == 0:
            f2.write(f"{float(i) + 0.5}\n")
        else:
            f2.write(f"{float(i) - 0.1}\n")
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

chmod -R 777 /home/user
