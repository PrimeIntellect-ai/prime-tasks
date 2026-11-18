#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gcc libc6-dev findutils coreutils
    pip3 install pytest

    mkdir -p /home/user/assets_extracted
    mkdir -p /home/user/csv_data
    mkdir -p /home/user/temp_setup/zips

    cat << 'EOF' > /home/user/temp_setup/1.csv
101,Apollo,active
102,Gemini,paused
103,Mercury,completed
EOF

    cat << 'EOF' > /home/user/temp_setup/2.csv
201,Voyager,active
202,Pioneer,completed
EOF

    cat << 'EOF' > /home/user/temp_setup/3.csv
301,Hubble,active
302,JamesWebb,active
EOF

    cat << 'EOF' > /home/user/temp_setup/4.csv
401,Cassini,completed
402,Galileo,completed
403,Juno,active
EOF

    cd /home/user/temp_setup
    zip zips/batch1.zip 1.csv 2.csv
    zip zips/batch2.zip 3.csv 4.csv

    cd zips
    tar -czvf /home/user/legacy_assets.tar.gz batch1.zip batch2.zip

    cd /home/user
    rm -rf /home/user/temp_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
