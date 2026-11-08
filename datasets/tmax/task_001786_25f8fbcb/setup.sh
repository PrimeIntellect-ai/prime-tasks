#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget tar libreadline-dev
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored
    mkdir -p /home/user/workspace

    # Download and vendor Lua 5.4.6
    cd /app/vendored
    wget https://www.lua.org/ftp/lua-5.4.6.tar.gz
    tar -xzf lua-5.4.6.tar.gz
    rm lua-5.4.6.tar.gz

    # Apply perturbation
    sed -i 's/-lm/-lbrokenmath/g' /app/vendored/lua-5.4.6/src/Makefile

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
    chmod -R 777 /app/vendored
