#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/staging

    python3 -c '
with open("/home/user/legacy_system.log", "wb") as f:
    f.write(b"LOG ENTRY 1: System started\n")
    f.write(b"LOG ENTRY 2: User login [SECRET_ID]\n")
    f.write(b"LOG ENTRY 3: R\xe9sum\xe9 processed for [SECRET_ID]\n")
    f.write(b"LOG ENTRY 4: System shutdown\n")
'

    chmod -R 777 /home/user
