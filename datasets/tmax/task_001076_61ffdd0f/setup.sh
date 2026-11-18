#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget binutils coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Download and extract vendored pyelftools
    mkdir -p /app/vendored
    cd /app/vendored
    wget -qO pyelftools.tar.gz https://files.pythonhosted.org/packages/source/p/pyelftools/pyelftools-0.31.tar.gz
    tar -xzf pyelftools.tar.gz
    rm pyelftools.tar.gz

    # Apply perturbation
    sed -i "s/b'\\\\x7fELF'/b'\\\\x7fFLE'/g" /app/vendored/pyelftools-0.31/elftools/elf/elffile.py

    # Setup corpus
    mkdir -p /home/user/elf_storage/clean
    mkdir -p /home/user/elf_storage/evil

    # Clean corpus
    cp /bin/ls /home/user/elf_storage/clean/ls_bin
    cp /bin/cat /home/user/elf_storage/clean/cat_bin
    cp /bin/echo /home/user/elf_storage/clean/echo_bin

    # Evil corpus
    echo -ne "\x7fBAD_ELF_DATA_CORRUPT" > /home/user/elf_storage/evil/corrupted_magic.elf

    cp /bin/ls /home/user/elf_storage/evil/bad_shoff.elf
    printf '\xff\xff\xff\xff\xff\xff\xff\xff' | dd of=/home/user/elf_storage/evil/bad_shoff.elf bs=1 seek=40 count=8 conv=notrunc

    cp /bin/true /home/user/elf_storage/evil/bloated.elf
    echo "bloat data" > /tmp/bloat.bin
    objcopy --add-section .storage_bloat=/tmp/bloat.bin /home/user/elf_storage/evil/bloated.elf
    rm /tmp/bloat.bin

    chmod -R 777 /home/user
    chmod -R 777 /app
