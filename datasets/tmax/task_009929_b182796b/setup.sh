#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ zip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create rules.ini
    cat << 'EOF' > /home/user/rules.ini
MODULE_DIR=/home/user/organized/modules
TEXT_DIR=/home/user/organized/docs
EOF

    # Create project_backup.tar.gz
    mkdir -p /tmp/backup_gen
    cd /tmp/backup_gen

    printf "Hello World\n" > readme.txt
    printf "\xDE\xCA\xFB\xADsome_core_data" > core.dat

    mkdir nested1
    printf "Notes here\n" > nested1/notes.md
    printf "\xDE\xCA\xFB\xADsome_lib_data" > nested1/lib.dat
    cd nested1
    zip ../nested1.zip notes.md lib.dat
    cd ..

    mkdir nested3
    printf "\xDE\xCA\xFB\xADsome_deep_data" > nested3/deep.dat
    cd nested3
    zip ../nested3.zip deep.dat
    cd ..

    mkdir nested2
    mv nested3.zip nested2/
    cd nested2
    tar -cf ../nested2.tar nested3.zip
    cd ..

    printf "\x00\x01\x02\x03ignore_this" > ignore_me.bin

    tar -czf /home/user/project_backup.tar.gz readme.txt core.dat nested1.zip nested2.tar ignore_me.bin

    rm -rf /tmp/backup_gen

    chmod -R 777 /home/user
