#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/project_data/dir1
mkdir -p /home/user/project_data/dir2
mkdir -p /home/user/processed

# Create infinite symlink loop
ln -s /home/user/project_data /home/user/project_data/dir1/loop_link

# Create binary files using Python to avoid printf escape issues
python3 -c '
with open("/home/user/project_data/file1.dat", "wb") as f:
    f.write(b"\x44\x41\x54\x00\x01\x05\x00\x00\x00HELLO")
with open("/home/user/project_data/dir2/file2.dat", "wb") as f:
    f.write(b"\x44\x41\x54\x00\x02\x04\x00\x00\x00TEST")
'

# Create log file 1: sys.log
cat << 'EOF' > /home/user/project_data/sys.log
[RECORD_START]
Info: System booted
All checks passed.
[RECORD_END]
[RECORD_START]
Warning: High memory usage
[CRITICAL] Out of memory!
Please restart.
[RECORD_END]
EOF

# Create log file 2 in dir1: app.log
cat << 'EOF' > /home/user/project_data/dir1/app.log
[RECORD_START]
User logged in
[RECORD_END]
[RECORD_START]
[CRITICAL] Database connection lost
Retrying in 5 seconds...
[RECORD_END]
[RECORD_START]
Retry failed.
[RECORD_END]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
