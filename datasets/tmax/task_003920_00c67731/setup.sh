#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/project_data/raw
    mkdir -p /home/user/project_data/processed

    python3 -c '
import os
with open("/home/user/project_data/raw/file1.dat", "wb") as f:
    f.write(b"Hellooo W\xf6rld!!!")
with open("/home/user/project_data/raw/file2.dat", "wb") as f:
    f.write(b"aaaabbbbccccDDDD")
with open("/home/user/project_data/raw/file3.dat", "wb") as f:
    f.write(b"Just a n\xf4rmal file...")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
