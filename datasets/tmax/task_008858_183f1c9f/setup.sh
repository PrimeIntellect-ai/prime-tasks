#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/remote_drop
    mkdir -p /home/user/incoming
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/baseline.csv
SRV_A,MEM_USED,4000
SRV_A,CPU_LOAD,10
SRV_B,MEM_USED,8000
SRV_B,DISK_IO,50
EOF

    cat << 'EOF' > /home/user/remote_drop/report_1.csv
R001,SRV_A,1600000000,MEM_USED,4100
R001,SRV_A,1600000000,CPU_LOAD,15
R001,SRV_A,1600000000,CPU_LOAD,15
R002,SRV_B,1600000010,MEM_USED,8200
R002,SRV_B,1600000010,DISK_IO,45
EOF

    cat << 'EOF' > /home/user/remote_drop/report_2.csv
R003,SRV_A,1600000020,MEM_USED,4200
R003,SRV_A,1600000020,CPU_LOAD,12
R004,SRV_B,1600000030,MEM_USED,8000
R004,SRV_B,1600000030,DISK_IO,50
R004,SRV_B,1600000030,DISK_IO,50
R005,SRV_A,1600000040,MEM_USED,4000
R005,SRV_A,1600000040,CPU_LOAD,10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
