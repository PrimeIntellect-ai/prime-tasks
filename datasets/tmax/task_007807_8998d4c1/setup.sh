#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c '
with open("/home/user/prog.bin", "wb") as f:
    f.write(b"\x01\x00\x00\x0A\x01\x01\x00\x01\x01\x02\x00\x01\x06\x00\x00\x03\x04\x01\x01\x00\x03\x00\x00\x02\x07\x00\x00\xFC\x08\x01\x00\x00\x09\x00\x00\x00")
'

    chmod -R 777 /home/user
