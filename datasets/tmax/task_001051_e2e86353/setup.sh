#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs

    cat << 'EOF' > /home/user/raw_logs/us.csv
1670000000,INFO,US,System started normal
1670000050,WARNING,US,High latency detected
MISSING,CRITICAL,US,Main database connection lost
1670000150,INFO,US,Retrying connection
1670000200,ERROR,US,Process 🛑 terminated
1670000250,INFO,US,Rebooting
EOF

    cat << 'EOF' > /home/user/raw_logs/eu.csv
1670000010,INFO,EU,Service up
1670000060,ERROR,EU,Disk usage at 90%
1670000100,INFO,EU,Clearing tmp files
MISSING,ERROR,EU,Backup 故障
1670000210,INFO,EU,Backup skipped
1670000260,CRITICAL,EU,Node failure
EOF

    cat << 'EOF' > /home/user/raw_logs/ap.csv
1670000020,INFO,AP,Initialization complete
1670000080,CRITICAL,AP,Memory leak 🛑
1670000110,INFO,AP,Allocating swap
1670000140,ERROR,AP,Swap allocation failed
MISSING,INFO,AP,User login
1670000220,ERROR,AP,Module 故障 detected
EOF

    chmod -R 777 /home/user
