#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils coreutils
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup directories
    mkdir -p /home/user/incoming
    mkdir -p /home/user/repo

    # Create a valid x86_64 ELF file
    cp /bin/true /home/user/incoming/core_engine.elf
    echo "Some log data" > /home/user/incoming/core_engine.meta
    echo "BUILD_VERSION=1.0.5" >> /home/user/incoming/core_engine.meta
    echo "More log data" >> /home/user/incoming/core_engine.meta

    # Create another valid x86_64 ELF file
    cp /bin/ls /home/user/incoming/auth_module.elf
    echo "BUILD_VERSION=3.2.0" > /home/user/incoming/auth_module.meta

    # Create a fake aarch64 ELF file by copying a valid ELF and patching the e_machine field
    cp /bin/true /home/user/incoming/net_worker.elf
    printf '\xB7' | dd of=/home/user/incoming/net_worker.elf bs=1 seek=18 count=1 conv=notrunc status=none
    echo "Log prefix" > /home/user/incoming/net_worker.meta
    echo "BUILD_VERSION=0.9.9-beta" >> /home/user/incoming/net_worker.meta

    # Create an invalid file with .elf extension
    echo "This is just text" > /home/user/incoming/readme.elf
    echo "BUILD_VERSION=9.9.9" > /home/user/incoming/readme.meta

    # Create a binary file with meta
    cp /bin/pwd /home/user/incoming/orphan_bin.elf
    echo "BUILD_VERSION=1.1.1" > /home/user/incoming/orphan_bin.meta

    # Permissions
    chown -R user:user /home/user/incoming
    chown -R user:user /home/user/repo
    chmod -R 777 /home/user
