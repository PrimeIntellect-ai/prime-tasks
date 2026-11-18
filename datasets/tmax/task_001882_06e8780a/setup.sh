#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/servers.csv
ServerID,CPU,Mem,Disk,NetIn,NetOut
S-01,45.0,60.0,500,10.0,5.0
S-02,,70.0,250,15.0,
S-03,150.0,80.0,100,20.0,10.0
S-04,40.0,55.0,500,11.0,6.0
S-05,42.0,,300,9.0,4.0
S-10,41.0,58.0,400,10.0,5.0
EOF

    mkdir -p /home/user/workspace
    mkdir -p /home/user/output

    chown -R user:user /home/user
    chmod -R 777 /home/user
