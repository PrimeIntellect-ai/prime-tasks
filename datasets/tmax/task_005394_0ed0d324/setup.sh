#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/replication_graph.csv
source_instance,target_instance,latency_ms
db-01,db-02,15
db-01,db-03,20
db-02,db-04,10
db-03,db-04,5
db-04,db-05,12
db-02,db-06,25
db-05,db-07,8
db-06,db-07,15
EOF

    cat << 'EOF' > /home/user/backup_sizes.csv
instance_id,backup_size_gb
db-01,50
db-02,12
db-03,8
db-04,100
db-05,45
db-06,30
db-07,60
db-08,500
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
