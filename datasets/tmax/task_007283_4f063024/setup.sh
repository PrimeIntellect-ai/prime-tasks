#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar coreutils
    pip3 install pytest

    mkdir -p /home/user/workspace_temp/raw
    mkdir -p /home/user/workspace_temp/links
    mkdir -p /home/user/archive_parts

    cat << 'EOF' > /home/user/workspace_temp/raw/data1.csv
sensor_a,10
sensor_b,42
sensor_c,99
EOF

    cat << 'EOF' > /home/user/workspace_temp/raw/data2.csv
sensor_b,11
sensor_a,15
EOF

    cat << 'EOF' > /home/user/workspace_temp/raw/data3.csv
sensor_x,1
sensor_a,25
sensor_a,5
EOF

    ln -s ../raw/data1.csv /home/user/workspace_temp/links/link_1.csv
    ln -s ../raw/data2.csv /home/user/workspace_temp/links/link_2.csv
    ln -s ../raw/missing.csv /home/user/workspace_temp/links/link_3.csv
    ln -s ../raw/data3.csv /home/user/workspace_temp/links/link_4.csv

    cat << 'EOF' > /home/user/workspace_temp/manifest.csv
path,description
links/link_1.csv,batch_01
links/link_2.csv,batch_02
links/link_3.csv,batch_03_missing
links/link_4.csv,batch_04
EOF

    cd /home/user/workspace_temp
    tar -czf ../dataset.tar.gz *
    cd /home/user
    split -b 150 dataset.tar.gz archive_parts/dataset.tar.gz.part_
    rm -rf /home/user/workspace_temp dataset.tar.gz

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/archive_parts
    chmod -R 777 /home/user
