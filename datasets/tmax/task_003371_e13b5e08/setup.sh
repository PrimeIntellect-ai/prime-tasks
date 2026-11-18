#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backups.csv
id,timestamp,db_name,status,size_bytes
1,1690000000,users_db,SUCCESS,1048576
2,1690000050,orders_db,FAILED,0
3,1690000100,graph_db,SUCCESS,2048
4,bad_time,users_db,SUCCESS,500
5,1690000200,logs_db,SUCCESS,-100
6,1690000300,analytics_db,SUCCESS,999999
7,1690000400,drop-table,SUCCESS,5000
EOF

    chmod -R 777 /home/user
