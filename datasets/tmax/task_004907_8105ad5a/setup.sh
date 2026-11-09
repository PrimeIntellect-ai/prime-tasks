#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config
    mkdir -p /home/user/data
    mkdir -p /home/user/extract

    cat << 'EOF' > /home/user/config/backup_system.ini
[manifests]
/home/user/data/manifest1.txt = utf-8
/home/user/data/manifest2.txt = iso-8859-1
EOF

    # UTF-8 manifest
    cat << 'EOF' > /home/user/data/manifest1.txt
file1.txt 1024
dir/file2.txt 2048
../../home/user/evil.sh 500
EOF

    # ISO-8859-1 manifest (hex encoding for cafe.txt to ensure proper byte representation)
    python3 -c "
with open('/home/user/data/manifest2.txt', 'wb') as f:
    f.write(b'legit_file.dat 4096\n')
    f.write(b'dir/caf\xe9.txt 100\n')
    f.write(b'../escape.txt 200\n')
"

    chown -R user:user /home/user/config /home/user/data /home/user/extract
    chmod -R 777 /home/user
