#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget protobuf-compiler
pip3 install pytest

# Install newer Go version
wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
rm go1.23.4.linux-amd64.tar.gz
export PATH="/usr/local/go/bin:$PATH"

# Install protoc plugins
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
cp /root/go/bin/protoc-gen-go* /usr/local/bin/

# Prepare user environment
mkdir -p /home/user/project/legacy
mkdir -p /home/user/project/test_data/subdir
mkdir -p /home/user/project/proto
mkdir -p /home/user/project/go_server/pb
mkdir -p /home/user/project/client

# Create legacy Python script
cat << 'EOF' > /home/user/project/legacy/dedup.py
import os
import hashlib

def find_duplicates(directory_path):
    # Ignores files strictly less than 15 bytes
    hashes = {}
    for root, dirs, files in os.walk(directory_path):
        for file in files:
            path = os.path.join(root, file)
            if os.path.getsize(path) < 15:
                continue
            with open(path, 'rb') as f:
                h = hashlib.sha256(f.read()).hexdigest()
                if h not in hashes:
                    hashes[h] = []
                hashes[h].append(path)

    duplicates = {h: paths for h, paths in hashes.items() if len(paths) > 1}
    for h in duplicates:
        duplicates[h].sort()
    return duplicates

if __name__ == "__main__":
    print(find_duplicates("/home/user/project/test_data"))
EOF

# Create test data
echo "This is some duplicate content." > /home/user/project/test_data/file1.txt
echo "This is some duplicate content." > /home/user/project/test_data/file2.txt
echo "This is some duplicate content." > /home/user/project/test_data/subdir/file3.txt
echo "This is unique content that is long enough." > /home/user/project/test_data/file4.txt
echo "short" > /home/user/project/test_data/file5.txt
echo "short" > /home/user/project/test_data/subdir/file6.txt

useradd -m -s /bin/bash user || true
echo 'export PATH="/usr/local/go/bin:/usr/local/bin:$PATH"' >> /home/user/.bashrc

chown -R user:user /home/user/project
chmod -R 777 /home/user
