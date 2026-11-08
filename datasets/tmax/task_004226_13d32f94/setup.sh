#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc make tar
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/microtar-0.1.0
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Download microtar source
    cd /app/vendored/microtar-0.1.0
    curl -sL https://raw.githubusercontent.com/rxi/microtar/master/src/microtar.c -o microtar.c
    curl -sL https://raw.githubusercontent.com/rxi/microtar/master/src/microtar.h -o microtar.h

    # Create broken Makefile
    cat << 'EOF' > Makefile
all:
        gcc -c microtar.c -o microtar.o -fbroken-flag
        ar rcs libmicrotar.a microtar.o
EOF

    # Create python script to generate tar files
    cat << 'EOF' > /tmp/gen_tars.py
import tarfile
import os

os.makedirs("/app/corpora/clean", exist_ok=True)
os.makedirs("/app/corpora/evil", exist_ok=True)

with tarfile.open("/app/corpora/clean/dataset1.tar", "w") as tar:
    info = tarfile.TarInfo("data/dataset.csv")
    info.size = 0
    tar.addfile(info)

with tarfile.open("/app/corpora/clean/dataset2.tar", "w") as tar:
    info = tarfile.TarInfo("images/01.png")
    info.size = 0
    tar.addfile(info)

with tarfile.open("/app/corpora/evil/evil1.tar", "w") as tar:
    info = tarfile.TarInfo("../etc/passwd")
    info.size = 0
    tar.addfile(info)

with tarfile.open("/app/corpora/evil/evil2.tar", "w") as tar:
    info = tarfile.TarInfo("/root/secret.txt")
    info.size = 0
    tar.addfile(info)

with tarfile.open("/app/corpora/evil/evil3.tar", "w") as tar:
    info = tarfile.TarInfo("data/../../home/user/.bashrc")
    info.size = 0
    tar.addfile(info)
EOF

    python3 /tmp/gen_tars.py
    rm /tmp/gen_tars.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
