#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/remote_in /home/user/remote_out /home/user/local_process

    cat << 'EOF' > /home/user/remote_in/data.csv
1,   AlIce JoneS
2,bObby   
3, ChArlie BrOwn
4,  DaviD   SmIth 
EOF

    cat << 'EOF' > /home/user/master_list.txt
alice jones
bob
charlie brown
david smith
david smyth
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
