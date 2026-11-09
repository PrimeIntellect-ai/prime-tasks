#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.csv
server_id,requests,errors
srv_01,100,5
srv_02,50,0
srv_03,-10,5
srv_04,20,25
srv_05,0,0
srv_06,200,15
srv_07,,
srv_08,abc,def
srv_09,500,20
srv_10,100,5
EOF

    chmod -R 777 /home/user
