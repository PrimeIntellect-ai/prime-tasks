#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar espeak gcc make
    pip3 install pytest

    mkdir -p /app/storage
    cd /app

    espeak -w /app/voicemail.wav "The system is failing. The emergency authorization code is echo. I repeat, echo."

    echo "filename,owner" > /app/inventory.csv

    create_manifest() {
        local bytes=$1
        echo '<?xml version="1.0" encoding="UTF-16"?><manifest><bytes>'$bytes'</bytes></manifest>' | iconv -f UTF-8 -t UTF-16LE > manifest.xml
    }

    create_manifest 4000000
    zip /app/storage/archive_01.zip manifest.xml
    echo "archive_01.zip,admin" >> /app/inventory.csv

    echo "This is not a valid zip" > /app/storage/archive_02.zip
    echo "archive_02.zip,admin" >> /app/inventory.csv

    create_manifest 4675309
    tar -czf /app/storage/archive_03.tar.gz manifest.xml
    echo "archive_03.tar.gz,admin" >> /app/inventory.csv

    create_manifest 0
    zip /app/storage/archive_04.zip manifest.xml
    echo "archive_04.zip,admin" >> /app/inventory.csv

    echo "Broken tarball data" > /app/storage/archive_05.tar.gz
    echo "archive_05.tar.gz,admin" >> /app/inventory.csv

    rm manifest.xml

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
