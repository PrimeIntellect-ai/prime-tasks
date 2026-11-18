#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Create user
useradd -m -s /bin/bash user || true

# Generate test files
cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile
import gzip

os.makedirs("/home/user/submissions", exist_ok=True)

# 1. team_alpha.tar.gz containing docs/api.md and legacy.zip (which contains v1.md)
os.makedirs("/tmp/alpha/docs", exist_ok=True)
with open("/tmp/alpha/docs/api.md", "w") as f:
    f.write("Line 1\nLine 2\nLine 3\n") # 3 lines

with zipfile.ZipFile("/tmp/alpha/legacy.zip", "w") as zf:
    zf.writestr("v1.md", "V1 Line 1\nV1 Line 2\nV1 Line 3\nV1 Line 4\nV1 Line 5\n") # 5 lines

with tarfile.open("/home/user/submissions/team_alpha.tar.gz", "w:gz") as tar:
    tar.add("/tmp/alpha/docs/api.md", arcname="docs/api.md")
    tar.add("/tmp/alpha/legacy.zip", arcname="legacy.zip")

# 2. team_beta.zip containing readme.md
with zipfile.ZipFile("/home/user/submissions/team_beta.zip", "w") as zf:
    zf.writestr("readme.md", "Beta Readme\nLine 2\n") # 2 lines

# 3. team_gamma.stream.gz (standalone compressed stream)
with gzip.open("/home/user/submissions/team_gamma.stream.gz", "wt") as f:
    f.write("Stream line 1\nStream line 2\nStream line 3\nStream line 4\n") # 4 lines
EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
