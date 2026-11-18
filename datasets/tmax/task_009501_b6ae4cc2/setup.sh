#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/project/.tmp
    mkdir -p /home/user/tar_source

    # Create existing project files
    echo -n "unchanged_content" > /home/user/project/app.log
    echo -n "v1_config" > /home/user/project/config.json
    mkdir -p /home/user/project/src
    echo -n "package main" > /home/user/project/src/main.go

    # Create tar source files
    echo -n "unchanged_content" > /home/user/tar_source/app.log
    echo -n "v2_config" > /home/user/tar_source/config.json
    echo -n "new_feature" > /home/user/tar_source/feature.go
    echo -n "malicious_data" > /home/user/tar_source/escape1.txt
    echo -n "malicious_data2" > /home/user/tar_source/escape2.txt

    # Create the tarball using python to inject malicious paths
    # Using addfile with modified TarInfo to prevent path sanitization
    cat << 'EOF' > /home/user/make_tar.py
import tarfile

with tarfile.open("/home/user/update.tar", "w") as tar:
    tar.add("/home/user/tar_source/app.log", arcname="app.log")
    tar.add("/home/user/tar_source/config.json", arcname="config.json")
    tar.add("/home/user/tar_source/feature.go", arcname="feature.go")

    info1 = tar.gettarinfo("/home/user/tar_source/escape1.txt")
    info1.name = "../escaped.txt"
    with open("/home/user/tar_source/escape1.txt", "rb") as f:
        tar.addfile(info1, f)

    info2 = tar.gettarinfo("/home/user/tar_source/escape2.txt")
    info2.name = "/etc/fake_root.txt"
    with open("/home/user/tar_source/escape2.txt", "rb") as f:
        tar.addfile(info2, f)
EOF

    python3 /home/user/make_tar.py
    rm -rf /home/user/tar_source /home/user/make_tar.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chown user:user /home/user/update.tar
    chmod -R 777 /home/user
