#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git qemu-utils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/storage
    mkdir -p /home/user/infra.git

    # Initialize bare git repository
    git init --bare /home/user/infra.git

    # Create QEMU images
    qemu-img create -f qcow2 /home/user/storage/small.qcow2 50M

    qemu-img create -f qcow2 /home/user/storage/large.qcow2 200M
    # Write random data to allocate actual disk space > 100MB
    dd if=/dev/urandom of=/home/user/storage/large.qcow2 conv=notrunc bs=1M count=110 seek=2

    qemu-img create -f qcow2 /home/user/storage/medium.qcow2 150M

    # Set up git config for the user to allow commits during testing
    su - user -c "git config --global user.email 'user@example.com' && git config --global user.name 'User'"

    chown -R user:user /home/user
    chmod -R 777 /home/user
