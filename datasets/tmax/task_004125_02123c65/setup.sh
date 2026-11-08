#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        inotify-tools \
        jq \
        unzip \
        zip \
        tar \
        gzip \
        file

    pip3 install pytest

    mkdir -p /home/user/test_data
    cd /home/user/test_data

    # Create good1.tar.gz
    mkdir good1
    echo "filename,owner,size_bytes" > good1_raw.csv
    echo "file1.dat,alice,100" >> good1_raw.csv
    echo "file2.dat,bob,200" >> good1_raw.csv
    iconv -f UTF-8 -t UTF-16LE good1_raw.csv > good1/metadata.csv
    tar -czf good1.tar.gz good1/
    rm -rf good1 good1_raw.csv

    # Create good2.zip
    mkdir good2
    echo "filename,owner,size_bytes" > good2_raw.csv
    echo "file3.dat,alice,50" >> good2_raw.csv
    echo "file4.dat,charlie,300" >> good2_raw.csv
    iconv -f UTF-8 -t ISO-8859-1 good2_raw.csv > good2/metadata.csv
    zip -r good2.zip good2/
    rm -rf good2 good2_raw.csv

    # Create evil1.tar.gz (Zip Slip)
    mkdir evil1
    touch evil1/safe.txt
    tar -cf evil1.tar evil1/safe.txt
    mkdir -p payload
    touch payload/hacked.txt
    tar -rf evil1.tar --transform='s|.*|../hacked.txt|' payload/hacked.txt || true
    gzip evil1.tar
    rm -rf evil1 payload

    # Create evil2.zip (Zip Slip)
    python3 -c "
import zipfile
with zipfile.ZipFile('evil2.zip', 'w') as z:
    z.writestr('../evil.txt', 'hacked')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
