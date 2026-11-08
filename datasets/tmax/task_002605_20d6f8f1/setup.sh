#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_repo
    cd /home/user/legacy_repo

    # Create binary blobs
    head -c 200 /dev/urandom > blob_A.blob
    head -c 600 /dev/urandom > blob_B.blob
    head -c 300 /dev/urandom > blob_C.blob
    head -c 1024 /dev/urandom > blob_D.blob

    # Create corrupted CSV
    printf "id|name|version|blob_file\r\n" > metadata.csv
    printf "ART-001|<b>CoreEngine</b>|1.0.0|blob_A.blob\r\n" >> metadata.csv
    printf "ART-002|PhysicsModule|1.2.4|blob_B.blob\r\n" >> metadata.csv
    printf "ART-003|<b>RenderPip</b>|2.1.0|blob_C.blob\r\n" >> metadata.csv
    printf "ART-004|AudioSys|3.0.1|blob_D.blob\r\n" >> metadata.csv

    chown -R user:user /home/user
    chmod -R 777 /home/user
