#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/doc_backup/section1/subsection
    mkdir -p /home/user/doc_backup/section2

    ln -s /home/user/doc_backup/section1 /home/user/doc_backup/section1/subsection/loop

    echo -n "Welcome to the API documentation." > /tmp/doc1.txt
    gzip -c /tmp/doc1.txt > /home/user/doc_backup/section1/api.txt.gz

    echo -n "Changelog: Fixed infinite loops." > /tmp/doc2.txt
    gzip -c /tmp/doc2.txt > /home/user/doc_backup/section2/changelog.txt.gz

    printf "\x7fELF\x02\x01\x01\x00FakeBinaryContent" > /tmp/fake_bin.elf
    gzip -c /tmp/fake_bin.elf > /home/user/doc_backup/section1/backup_tool.gz

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/doc_backup
    chmod -R 777 /home/user
