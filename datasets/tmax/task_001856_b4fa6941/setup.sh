#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/raw_backups
    cd /home/user/raw_backups

    printf "HEADER_TYPE_ALPHbody_A_content_123" > file_A.dat
    printf "HEADER_TYPE_BETAbody_B_content_456" > file_B.dat
    printf "HEADER_TYPE_ALPHbody_C_content_789" > file_C.dat
    printf "HEADER_TYPE_GAMMbody_D_content_000" > file_D.dat

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
