#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_backups/module_a
    mkdir -p /home/user/project_backups/module_b/deep_dir

    # Create valid zips
    echo "int main() { return 0; }" > /tmp/main.cpp
    echo "void test() {}" > /tmp/test.cpp

    cd /tmp
    zip -q /home/user/project_backups/module_a/backup1.zip main.cpp
    zip -q /home/user/project_backups/module_b/backup2.zip test.cpp
    zip -q /home/user/project_backups/module_b/deep_dir/backup3.zip main.cpp test.cpp

    # Create corrupt zips (valid header, truncated body, or just random junk)
    head -c 50 /home/user/project_backups/module_a/backup1.zip > /home/user/project_backups/module_a/backup_broken1.zip
    echo "not a zip file" > /home/user/project_backups/module_b/deep_dir/backup_broken2.zip

    chmod -R 777 /home/user
