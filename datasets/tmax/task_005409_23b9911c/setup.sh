#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/dirA
    mkdir -p /home/user/data/dirB/sub

    # Create original files
    echo "Hello World" > /home/user/data/file1.txt
    echo "Test Content" > /home/user/data/dirA/file3.txt

    # Create duplicate files (separate inodes initially)
    echo "Hello World" > /home/user/data/file2.txt
    echo "Test Content" > /home/user/data/dirA/file4.txt

    # Create .tmp files
    echo "garbage" > /home/user/data/dirB/temp1.tmp
    echo "garbage" > /home/user/data/dirB/temp2.tmp
    echo "garbage" > /home/user/data/dirB/sub/temp3.tmp
    echo "garbage" > /home/user/data/root.tmp

    # Create duplicates.csv
    cat << EOF > /home/user/duplicates.csv
/home/user/data/file1.txt,/home/user/data/file2.txt
/home/user/data/dirA/file3.txt,/home/user/data/dirA/file4.txt
EOF

    chown -R user:user /home/user/data
    chown user:user /home/user/duplicates.csv

    chmod -R 777 /home/user
