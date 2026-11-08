#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget bzip2 make g++ p7zip-full
    pip3 install pytest

    mkdir -p /app
    wget -qO p7zip.tar.bz2 "https://sourceforge.net/projects/p7zip/files/p7zip/16.02/p7zip_16.02_src_all.tar.bz2/download"
    tar -xjf p7zip.tar.bz2 -C /app
    rm p7zip.tar.bz2

    sed -i 's/CXX=g++/CXX=g++++/' /app/p7zip_16.02/makefile.machine

    mkdir -p /tmp/dummy_logs
    dd if=/dev/urandom of=/tmp/dummy_logs/log1.txt bs=1024 count=2
    dd if=/dev/urandom of=/tmp/dummy_logs/log2.txt bs=1024 count=2

    cd /tmp
    7z a -v2k project_logs.7z dummy_logs/
    mkdir -p /home/user
    mv project_logs.7z.001 /home/user/
    mv project_logs.7z.002 /home/user/
    rm -rf /tmp/dummy_logs project_logs.7z*

    apt-get remove --purge -y p7zip-full p7zip
    apt-get autoremove -y

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/clean1.log
[RECORD_START]
This is a clean record.
Everything is fine.
[RECORD_END]
EOF

    printf "[RECORD_START]\nThis is an evil record.\n\x7fELF inside.\n[RECORD_END]\n" > /app/corpus/evil/evil1.log
    printf "[RECORD_START]\nThis is an evil record with PNG.\n\x89PNG inside.\n[RECORD_END]\n" > /app/corpus/evil/evil2.log

    cat << 'EOF' > /app/corpus/evil/evil3.log
[RECORD_START]
Missing end tag.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
