#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/tracker_config.ini
[Settings]
target_dir = /home/user/extracted
allowed_exts = .conf,.json,.xml
EOF

    cat << 'EOF' > /tmp/setup_tar.py
import tarfile
import os

os.makedirs("/home/user", exist_ok=True)

with tarfile.open("/home/user/backup.tar", "w") as tar:
    def add_file(filename, content, arcname):
        with open(filename, "w") as f:
            f.write(content)
        info = tar.gettarinfo(filename, arcname=arcname)
        info.name = arcname # Force exact name
        with open(filename, "rb") as f:
            tar.addfile(info, f)
        os.remove(filename)

    add_file("valid1.conf", "server { listen 80; }", "nginx/valid1.conf")
    add_file("valid2.txt", "readme", "nginx/valid2.txt")
    add_file("valid3.json", '{"key": "value"}', "app/valid3.json")
    add_file("mal1.sh", "echo 'hacked'", "/etc/cron.d/mal1.sh")
    add_file("mal2.conf", "bad config", "../ssh/mal2.conf")
    add_file("mal3.xml", "<xml></xml>", "nginx/../../mal3.xml")
EOF

    python3 /tmp/setup_tar.py
    rm /tmp/setup_tar.py

    chmod -R 777 /home/user
