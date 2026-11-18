#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ tar coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project_scatter/dirA/dirB
mkdir -p /home/user/project_scatter/dirC
mkdir -p /home/user/project_scatter/dirA/dirD

# Create dummy content
mkdir -p /tmp/dummy_project
echo "PROJECT_ID: ALPHA_7782_OMEGA" > /tmp/dummy_project/manifest.txt
# Add padding to ensure the tarball is large enough to produce at least 4 chunks
head -c 1000 /dev/urandom | base64 > /tmp/dummy_project/data1.bin
head -c 1000 /dev/urandom | base64 > /tmp/dummy_project/data2.bin

# Create the tarball
cd /tmp
tar -czf /tmp/dummy_project.tar.gz -C /tmp/dummy_project .

# Split the tarball into 100-byte chunks
split -b 100 /tmp/dummy_project.tar.gz /tmp/chunk_

# Rename and scatter chunks
mv /tmp/chunk_aa /home/user/project_scatter/dirA/file_part1.chunk
mv /tmp/chunk_ab /home/user/project_scatter/dirC/random_part2.chunk
mv /tmp/chunk_ac /home/user/project_scatter/dirA/dirB/stuff_part3.chunk
mv /tmp/chunk_ad /home/user/project_scatter/dirA/dirD/backup_part4.chunk

# Handle any remaining chunks dynamically
counter=5
for f in /tmp/chunk_*; do
    if [ -f "$f" ]; then
        mv "$f" "/home/user/project_scatter/archive_part${counter}.chunk"
        counter=$((counter + 1))
    fi
done

# Fix permissions
chown -R user:user /home/user/project_scatter
chmod -R 777 /home/user
