#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang dos2unix file
    pip3 install pytest

    mkdir -p /home/user/restored
    cd /home/user

    # Create source files for the tar
    mkdir -p temp_build/dir
    # File 1: UTF-16LE with CRLF
    echo -ne "\xFF\xFE" > temp_build/file_a.txt
    echo -n "SERVER_LEGACY" | iconv -f UTF-8 -t UTF-16LE >> temp_build/file_a.txt
    echo -ne "\x0D\x00\x0A\x00" >> temp_build/file_a.txt
    echo -n "System Data" | iconv -f UTF-8 -t UTF-16LE >> temp_build/file_a.txt

    # File 2: Windows-1252 with CRLF
    echo -e "Start\r\nSERVER_LEGACY\r\nEnd" | iconv -f UTF-8 -t WINDOWS-1252 > temp_build/dir/file_b.txt

    # Malicious file contents
    echo "echo 'hacked'" > temp_build/hacked.sh

    # Python script to build a tar file with a malicious path
    cat << 'EOF' > build_tar.py
import tarfile
import os

with tarfile.open('backup.tar', 'w') as tar:
    tar.add('temp_build/file_a.txt', arcname='file_a.txt')
    tar.add('temp_build/dir/file_b.txt', arcname='dir/file_b.txt')

    # Add malicious entry
    malicious = tarfile.TarInfo(name='../etc/hacked.sh')
    with open('temp_build/hacked.sh', 'rb') as f:
        data = f.read()
    malicious.size = len(data)
    tar.addfile(malicious, open('temp_build/hacked.sh', 'rb'))
EOF

    python3 build_tar.py
    rm -rf temp_build build_tar.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
