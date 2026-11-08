#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    mkdir -p /home/user/raw_data
    cd /home/user/raw_data

    cat << 'EOF' > dataset.ini
[Mappings]
SENS1042=Subject_Xenon
SENS9921=Subject_Argon
SENS0018=Subject_Krypton
SENS4444=Subject_Radon
EOF

    printf "SENS1042\x00\x01\x02\x03\x04" > file_a.dat
    printf "SENS9921\xFF\xFF\x00\x00\x11" > file_b.dat
    printf "SENS0018\x0A\x0B\x0C\x0D\x0E" > file_c.dat
    printf "CORR9999\x00\x00\x00\x00\x00" > file_d.dat
    printf "SENS4444\x12\x34\x56\x78\x90" > file_e.dat

    cd /home/user
    tar -czf inner.tar.gz raw_data/
    zip incoming_data.zip inner.tar.gz

    rm -rf raw_data inner.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
