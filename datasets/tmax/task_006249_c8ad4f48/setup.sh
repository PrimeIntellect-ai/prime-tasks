#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_files/
    echo -n "// ARCH: x86\nint main(){return 0;}" > /home/user/raw_files/a.c
    echo -n "// ARCH: arm\nint main(){return 1;}" > /home/user/raw_files/b.c
    echo -n "# ARCH: any\nprint('hello world!')" > /home/user/raw_files/c.py
    echo -n "// ARCH: x86\nint x=1;int y=2;int z=3;" > /home/user/raw_files/d.c
    echo -n "// ARCH: arm\nint x=1;int y=2;int z=4;" > /home/user/raw_files/e.c
    echo -n "# ARCH: any\nprint('just testing')" > /home/user/raw_files/f.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
