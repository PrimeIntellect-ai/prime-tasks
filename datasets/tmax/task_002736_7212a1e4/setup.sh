#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar espeak
    pip3 install pytest

    # Create nested archives
    mkdir -p /home/user/tmp_archive/docs1 /home/user/tmp_archive/docs2

    for i in $(seq 1 10); do
        echo "This is file $i" > /home/user/tmp_archive/docs1/file${i}.txt
    done
    for i in $(seq 11 25); do
        echo "This is file $i" > /home/user/tmp_archive/docs2/file${i}.txt
    done

    cd /home/user/tmp_archive/docs1
    zip -r ../docs1.zip ./*
    cd ../docs2
    tar -czf ../docs2.tar.gz ./*
    cd ..
    tar -cf /home/user/docs_archive.tar docs1.zip docs2.tar.gz

    cd /
    rm -rf /home/user/tmp_archive

    # Create audio file
    mkdir -p /app
    espeak -w /app/dictation.wav "The secret project codename is VANGUARD."

    # Setup user and permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
