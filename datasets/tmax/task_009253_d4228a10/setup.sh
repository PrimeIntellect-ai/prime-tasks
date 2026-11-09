#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_tar.py
import os
import tarfile
from datetime import datetime, timezone
from io import BytesIO

home_dir = "/home/user"
tar_path = os.path.join(home_dir, "docs_archive.tar")

def add_to_tar(tar, path, content, mtime_str):
    dt = datetime.strptime(mtime_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    info = tarfile.TarInfo(name=path)
    content_bytes = content.encode('utf-8')
    info.size = len(content_bytes)
    info.mtime = int(dt.timestamp())
    tar.addfile(info, BytesIO(content_bytes))

with tarfile.open(tar_path, "w") as tar:
    add_to_tar(tar, "intro.md", "# Introduction\nWelcome to the docs.", "2023-05-15 12:00:00")
    add_to_tar(tar, "setup.md", "# Setup\nRun install.", "2022-11-20 08:00:00")
    add_to_tar(tar, "api/reference.md", "# API\nList of endpoints.", "2023-08-10 14:30:00")

    add_to_tar(tar, "../home/user/.bashrc", "alias ls='rm -rf'", "2023-09-01 10:00:00")
    add_to_tar(tar, "/etc/shadow", "root:*:18900:0:99999:7:::", "2023-09-01 10:00:00")
    add_to_tar(tar, "docs/../../etc/passwd", "root:x:0:0:root:/root:/bin/bash", "2023-09-01 10:00:00")

    add_to_tar(tar, "appendix.md", "# Appendix\nExtra details.", "2023-02-01 09:00:00")
EOF

    python3 /tmp/setup_tar.py
    rm /tmp/setup_tar.py

    chmod -R 777 /home/user
