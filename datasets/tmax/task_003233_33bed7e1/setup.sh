#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gzip coreutils
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/repo/alpha/beta
    mkdir -p /home/user/repo/gamma
    mkdir -p /home/user/repo/delta/epsilon

    # Create files
    echo -n "chunk_A_data_" > /home/user/repo/alpha/1.dat
    echo -n "chunk_B_data_" > /home/user/repo/alpha/beta/2.dat
    echo -n "active_process_writing" > /home/user/repo/gamma/active.dat
    echo -n "chunk_C_data_" > /home/user/repo/gamma/3.dat
    echo -n "chunk_D_data" > /home/user/repo/delta/epsilon/4.dat

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
