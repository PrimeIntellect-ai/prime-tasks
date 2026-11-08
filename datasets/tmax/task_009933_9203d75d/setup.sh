#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/historical_jobs.csv
JobID,CPU_Cores,RAM_GB,Disk_IOps,Job_Duration
1,2,4,100,120.5
2,4,8,200,85.0
3,8,16,500,45.5
4,16,32,1000,20.0
5,2,8,150,110.0
6,4,16,250,75.0
7,8,32,600,40.0
8,16,64,1200,15.5
EOF

    cat << 'EOF' > /home/user/queries.csv
QueryID,CPU_Cores,RAM_GB,Disk_IOps
Q1,4,8,250
Q2,12,24,800
Q3,2,4,100
Q4,16,64,1500
EOF

    chmod -R 777 /home/user
