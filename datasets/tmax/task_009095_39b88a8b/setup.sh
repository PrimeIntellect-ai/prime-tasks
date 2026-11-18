#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_updates.csv
timestamp,service_name,metric_name,metric_value
1,auth,max_conns,10.0
2,db,timeout,50.0
3,auth,max_conns,12.0
4,auth,max_conns,14.0
5,db,timeout,52.0
6,auth,max_conns,16.0
7,cache,mem,1024.0
8,db,timeout,55.0
9,auth,max_conns,16.0
10,cache,mem,2048.0
11,db,timeout,58.0
12,db,timeout,60.0
EOF

    chmod -R 777 /home/user
