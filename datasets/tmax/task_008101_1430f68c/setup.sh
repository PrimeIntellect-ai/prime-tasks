#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data_dir/subdir
cd /home/user

# Create older files
echo "data1" > data_dir/file1.txt
echo "data2" > data_dir/file2.txt
echo "data3" > data_dir/subdir/file3.txt

# Set specific mtimes
touch -m -t 202301010000 data_dir/file1.txt
touch -m -t 202301010000 data_dir/file2.txt
touch -m -t 202301010000 data_dir/subdir/file3.txt

# Create base backup
tar -czf base_backup.tar.gz data_dir/file1.txt data_dir/file2.txt data_dir/subdir/file3.txt

# Modify some files to simulate changes since base backup
echo "data2_changed" > data_dir/file2.txt
touch -m -t 202301020000 data_dir/file2.txt

# Add a new file
echo "data4" > data_dir/new_file.txt
touch -m -t 202301020000 data_dir/new_file.txt

# Add a malicious symlink that causes infinite loops if followed
ln -s ../ data_dir/subdir/loop

# Create a dummy buggy script
cat << 'EOF' > /home/user/buggy_backup.py
import os, tarfile, sys, argparse

parser = argparse.ArgumentParser()
parser.add_argument('--dir', required=True)
parser.add_argument('--base', required=True)
parser.add_argument('--out', required=True)
args = parser.parse_args()

with tarfile.open(args.out, "w:gz") as tar:
    for root, dirs, files in os.walk(args.dir, followlinks=True):
        for f in files:
            filepath = os.path.join(root, f)
            arcname = os.path.relpath(filepath, os.path.dirname(args.dir))
            tar.add(filepath, arcname=arcname)
EOF

chmod -R 777 /home/user
