#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip libssl-dev zip unzip bzip2 tar g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import shutil
import subprocess

os.makedirs("/home/user/repository", exist_ok=True)

def make_file(path, is_elf, content=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        if is_elf:
            f.write(b"\x7fELF" + content)
        else:
            f.write(content)

# module A
make_file("/home/user/repository/moduleA/bin/server", True, b"server_data")
make_file("/home/user/repository/moduleA/bin/client", True, b"client_data")
make_file("/home/user/repository/moduleA/readme.txt", False, b"This is a readme")

subprocess.run(["zip", "-r", "../moduleA.zip", "bin", "readme.txt"], cwd="/home/user/repository/moduleA")

# module B / lib
make_file("/home/user/repository/moduleB/lib_source/libcore.so", True, b"core_lib")
make_file("/home/user/repository/moduleB/lib_source/libnet.so", True, b"net_lib")
make_file("/home/user/repository/moduleB/lib_source/notes.md", False, b"Library notes")

subprocess.run(["tar", "-czf", "lib.tar.gz", "-C", "lib_source", "."], cwd="/home/user/repository/moduleB")

make_file("/home/user/repository/moduleB/data/config.json", False, b"{}")

subprocess.run(["tar", "-cjf", "../moduleB.tar.bz2", "data", "lib.tar.gz"], cwd="/home/user/repository/moduleB")

# create top level tar
subprocess.run(["tar", "-czf", "/home/user/repository.tar.gz", "moduleA.zip", "moduleB.tar.bz2"], cwd="/home/user/repository")

# clean up
shutil.rmtree("/home/user/repository")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
