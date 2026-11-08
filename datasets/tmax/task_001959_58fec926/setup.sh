#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/storage

    cat << 'EOF' > /home/user/storage/config.ini
[Paths]
SafeDirectory = /home/user/storage/extracted
EOF

    cat << 'EOF' > /tmp/create_tar.py
import tarfile
import os
import io

os.makedirs("/home/user/storage", exist_ok=True)
with tarfile.open("/home/user/storage/incoming.tar", "w") as tar:
    # Safe file
    info = tarfile.TarInfo(name="logs/app.log")
    info.size = 5
    tar.addfile(info, fileobj=io.BytesIO(b"12345"))

    # Safe symlink (points inside)
    info_sym = tarfile.TarInfo(name="logs/latest.log")
    info_sym.type = tarfile.SYMTYPE
    info_sym.linkname = "app.log"
    tar.addfile(info_sym)

    # Unsafe symlink 1 (absolute path)
    info_unsym1 = tarfile.TarInfo(name="logs/system_passwd")
    info_unsym1.type = tarfile.SYMTYPE
    info_unsym1.linkname = "/etc/passwd"
    tar.addfile(info_unsym1)

    # Unsafe symlink 2 (relative path traversal)
    info_unsym2 = tarfile.TarInfo(name="logs/escape_hatch")
    info_unsym2.type = tarfile.SYMTYPE
    info_unsym2.linkname = "../../config.ini"
    tar.addfile(info_unsym2)
EOF

    python3 /tmp/create_tar.py
    rm /tmp/create_tar.py

    chmod -R 777 /home/user
