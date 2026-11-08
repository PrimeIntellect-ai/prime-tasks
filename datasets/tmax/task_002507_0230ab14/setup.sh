#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget tar gawk
    pip3 install pytest pandas scikit-learn

    # Create /app directory and download GNU datamash
    mkdir -p /app
    cd /app
    wget -q https://ftp.gnu.org/gnu/datamash/datamash-1.8.tar.gz
    tar -xzf datamash-1.8.tar.gz
    mv datamash-1.8 datamash-1.20
    rm datamash-1.8.tar.gz

    # Inject the deliberate perturbation at line 50 of src/datamash.c
    sed -i '50i #error "Deliberate perturbation: remove this line"' /app/datamash-1.20/src/datamash.c

    # Ensure the directory is writable so the user can compile it
    chmod -R 777 /app/datamash-1.20

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
