#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gzip tar
    pip3 install pytest

    mkdir -p /home/user/backups/proj_alpha
    mkdir -p /home/user/backups/proj_beta/old

    echo "TargetDirectory=/home/user/backups" > /home/user/config.txt

    python3 -c '
import gzip
def w(p, c):
    with gzip.open(p, "wb") as f:
        f.write(c)
w("/home/user/backups/proj_alpha/test1.gz", b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00")
w("/home/user/backups/proj_alpha/test2.gz", b"\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00")
w("/home/user/backups/proj_beta/doc.gz", b"Hello world")
w("/home/user/backups/proj_beta/old/core.gz", b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
