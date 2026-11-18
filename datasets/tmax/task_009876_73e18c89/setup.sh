#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Create directories
mkdir -p /home/user/artifact_repo/binaries/v1
mkdir -p /home/user/artifact_repo/binaries/v2/nested

# Create real binary files
echo "binary data 1" > /home/user/artifact_repo/binaries/v1/core.bin
echo "binary data 2" > /home/user/artifact_repo/binaries/v2/util.bin
echo "binary data 3" > /home/user/artifact_repo/binaries/valid_pkg.bin

# Create infinite symlink loops
ln -s /home/user/artifact_repo/binaries/v2/nested /home/user/artifact_repo/binaries/v2/nested/loop
ln -s /home/user/artifact_repo/binaries/v1 /home/user/artifact_repo/binaries/v1/latest

# Create the log file
cat << 'EOF' > /home/user/artifact_repo/curation.log
{
  "artifact_id": "pkg-101",
  "path": "binaries/v1/core.bin",
  "checksum": "a1b2c3d4",
  "status": "staged"
}
---
{
  "artifact_id": "pkg-102",
  "path": "binaries/v2/nested/loop/util.bin",
  "checksum": "deadbeef",
  "status": "staged"
}
---
{
  "artifact_id": "pkg-103",
  "path": "binaries/valid_pkg.bin",
  "checksum": "12345678",
  "status": "staged"
}
---
{
  "artifact_id": "pkg-104",
  "path": "binaries/v1/latest/core.bin",
  "checksum": "a1b2c3d4",
  "status": "archived"
}
---
{
  "artifact_id": "pkg-105",
  "path": "binaries/v2/util.bin",
  "checksum": "87654321",
  "status": "staged"
}
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
