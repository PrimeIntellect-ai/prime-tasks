#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/app_logs.csv
Timestamp,UserID,Message
1633089600,U1,システム故障が発生しました
1633091000,U2,Normal operation expected
1633093200,U3,Критический Сбой системы
1633094000,U4,Незначительный Сбой сети
1633096800,U5,All good here
EOF

    cat << 'EOF' > /home/user/sys_metrics.csv
Timestamp,CPU_Load,Mem_Load
2021-10-01T12:15:00Z,2.5,40.0
2021-10-01T12:45:00Z,3.1,42.0
2021-10-01T13:05:00Z,4.0,50.0
2021-10-01T13:55:00Z,1.2,30.0
2021-10-01T14:10:00Z,0.8,20.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
