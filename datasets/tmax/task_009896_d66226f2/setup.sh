#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip xxd file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    bash -c '
    mkdir -p /home/user/artifacts
    mkdir -p /tmp/work1 /tmp/work2

    # Create ISO-8859-1 text files
    echo -ne "Cr\xe8me br\xfbl\xe9e\n" > /tmp/work1/doc1.txt
    echo -ne "El Ni\xf1o\n" > /tmp/work2/doc2.txt

    # Create binary blob files
    echo -ne "\xde\xad\xbe\xef\x00\x01\x02\x03" > /tmp/work1/data1.blob
    echo -ne "\xca\xfe\xba\xbe\x04\x05\x06\x07" > /tmp/work2/data2.blob

    # Zip them up
    cd /tmp/work1 && zip /home/user/artifacts/file1.dat doc1.txt data1.blob
    cd /tmp/work2 && zip /home/user/artifacts/file2.bin doc2.txt data2.blob

    # Create a fake zip
    echo -ne "This is not a zip file, despite what you might think." > /home/user/artifacts/fake.zip

    # Clean up
    rm -rf /tmp/work1 /tmp/work2
    '

    chmod -R 777 /home/user
