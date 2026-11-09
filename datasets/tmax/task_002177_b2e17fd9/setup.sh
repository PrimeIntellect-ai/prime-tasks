#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_root/dirA
    mkdir -p /home/user/project_root/dirB
    mkdir -p /home/user/project_root/configs
    mkdir -p /home/user/project_root/docs

    echo "data A" > /home/user/project_root/dirA/fileA.txt
    echo "data B" > /home/user/project_root/dirB/fileB.txt

    cat << 'EOF' > /home/user/project_root/configs/db.conf
USER=admin
PASSWORD=supersecret
PORT=8080
EOF

    cat << 'EOF' > /home/user/project_root/configs/api.conf
USER=guest
PASSWORD=guestpass
HOST=localhost
EOF

    echo "General documentation" > /home/user/project_root/docs/readme.txt

    ln -s /home/user/project_root/dirB /home/user/project_root/dirA/link_to_B
    ln -s /home/user/project_root/dirA /home/user/project_root/dirB/link_to_A
    ln -s /home/user/project_root/nonexistent_dir /home/user/project_root/docs/broken_link
    ln -s /home/user/project_root/docs/readme.txt /home/user/project_root/dirA/readme_link

    cat << 'EOF' > /home/user/backup_script.py
import os
import tarfile

def make_backup(src_dir, dest_archive):
    with tarfile.open(dest_archive, "w:gz") as tar:
        for root, dirs, files in os.walk(src_dir, followlinks=True):
            for file in files:
                file_path = os.path.join(root, file)
                tar.add(file_path, arcname=os.path.relpath(file_path, src_dir))

if __name__ == "__main__":
    make_backup("/home/user/project_root", "/home/user/safe_archive.tar.gz")
EOF

    chmod -R 777 /home/user
