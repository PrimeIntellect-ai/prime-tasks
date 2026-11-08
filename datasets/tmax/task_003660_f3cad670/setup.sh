#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/dnastat

    echo -n "ACTGAATCGAATCG" > /home/user/data/seq1.txt
    echo -n "AGCAGCAGCAGCAGC" > /home/user/data/seq2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
