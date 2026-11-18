#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils tar gzip gawk bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/doc_repo
    mkdir -p /home/user/backup

    # Generate original files
    for i in $(seq -w 1 100); do
        echo "Documentation file $i - Original content" > /home/user/doc_repo/doc_$i.txt
    done

    # Create checksums
    cd /home/user/doc_repo
    sha256sum *.txt > /home/user/backup/full_checksums.txt

    # Modify some existing files
    echo "Updated content" >> /home/user/doc_repo/doc_015.txt
    echo "Updated content" >> /home/user/doc_repo/doc_042.txt
    echo "Updated content" >> /home/user/doc_repo/doc_088.txt

    # Create new files
    echo "New documentation A" > /home/user/doc_repo/doc_101.txt
    echo "New documentation B" > /home/user/doc_repo/doc_102.txt

    chown -R user:user /home/user/doc_repo /home/user/backup
    chmod -R 777 /home/user
