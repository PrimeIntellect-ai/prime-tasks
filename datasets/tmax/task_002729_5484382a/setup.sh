#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar build-essential python3-dev
    pip3 install pytest

    # Create directories
    mkdir -p /app

    # Download and extract bsdiff4-1.2.4
    curl -sL https://files.pythonhosted.org/packages/source/b/bsdiff4/bsdiff4-1.2.4.tar.gz -o /tmp/bsdiff4.tar.gz
    tar -xzf /tmp/bsdiff4.tar.gz -C /app
    rm /tmp/bsdiff4.tar.gz

    # Introduce perturbation in setup.py
    sed -i 's/bsdiff4\/core.c/bsdiff4\/core_broken.c/g' /app/bsdiff4-1.2.4/setup.py

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/project /home/user/backup_dir

    # Create mock base files in backup_dir
    head -c 1000000 </dev/urandom > /home/user/backup_dir/data.bin
    head -c 500000 </dev/urandom > /home/user/backup_dir/logs.txt

    # Create new state in project dir (simulating small appends/changes)
    cp /home/user/backup_dir/data.bin /home/user/project/data.bin
    cp /home/user/backup_dir/logs.txt /home/user/project/logs.txt
    echo "NEW LOG ENTRY 1" >> /home/user/project/logs.txt
    echo "NEW LOG ENTRY 2" >> /home/user/project/logs.txt
    head -c 1024 </dev/urandom >> /home/user/project/data.bin

    chmod -R 777 /home/user
    chmod -R 777 /app
