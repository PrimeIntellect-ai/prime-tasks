#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data_volume/logs
    mkdir -p /home/user/data_volume/dumps

    # File 1: Old and large enough, .txt (Will be RLE compressed)
    python3 -c "print('A' * 15000, end='')" > /home/user/data_volume/logs/fileA.txt
    touch -t 202212011200 /home/user/data_volume/logs/fileA.txt

    # File 2: Old and large enough, .txt (Will be RLE compressed)
    python3 -c "print('B' * 12000, end='')" > /home/user/data_volume/logs/fileB.txt
    touch -t 202212151200 /home/user/data_volume/logs/fileB.txt

    # File 3: Old and large enough, .bin (Will be gzip compressed)
    head -c 20000 /dev/urandom > /home/user/data_volume/dumps/dataC.bin
    touch -t 202211011200 /home/user/data_volume/dumps/dataC.bin

    # File 4: Large enough, but too new (Should be skipped)
    python3 -c "print('C' * 15000, end='')" > /home/user/data_volume/logs/fileD.txt
    touch -t 202305011200 /home/user/data_volume/logs/fileD.txt

    # File 5: Old, but too small (Should be skipped)
    python3 -c "print('D' * 5000, end='')" > /home/user/data_volume/dumps/dataE.bin
    touch -t 202210011200 /home/user/data_volume/dumps/dataE.bin

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data_volume
    chmod -R 777 /home/user
