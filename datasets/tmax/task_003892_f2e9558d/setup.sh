#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset

    # Create UTF-16LE encoded files
    echo -n -e "Record 1: Alpha\n" | iconv -f UTF-8 -t UTF-16LE > /home/user/dataset/chunk_001.dat
    echo -n -e "Record 2: Beta\n" | iconv -f UTF-8 -t UTF-16LE > /home/user/dataset/chunk_002.dat
    echo -n -e "Record 3: Gamma\n" | iconv -f UTF-8 -t UTF-16LE > /home/user/dataset/chunk_003.dat

    # Create the symlink loop
    ln -s /home/user/dataset /home/user/dataset/loop_link
    # Create a dummy symlink that looks like a dat file but points to a directory
    ln -s /home/user/dataset /home/user/dataset/chunk_loop.dat

    chown -R user:user /home/user/dataset
    chmod -R 777 /home/user
