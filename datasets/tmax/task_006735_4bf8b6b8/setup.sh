#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data/logs
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/logs/log_2023-10-01.csv
date,session_id,status,notes
2023-10-01,1001,SUCCESS,Normal operation
2023-10-01,1002,ERROR,Connection timeout
after 30 seconds
2023-10-01,1003,SUCCESS,User logged in
2023-10-01,1001,SUCCESS,Normal operation
EOF

    cat << 'EOF' > /home/user/data/logs/log_2023-10-02.csv
date,session_id,status,notes
2023-10-02,2001,SUCCESS,File uploaded
2023-10-02,2002,WARNING,Disk space low
clean up required
immediately
2023-10-02,2003,SUCCESS,Batch job complete
EOF

    cat << 'EOF' > /home/user/data/logs/log_2023-10-03.csv
date,session_id,status,notes
2023-10-03,3001,SUCCESS,Routine check
EOF

    cat << 'EOF' > /home/user/data/logs/log_2023-10-04.csv
date,session_id,status,notes
2023-10-04,4001,SUCCESS,Normal operation
2023-10-04,4002,ERROR,Database locked
2023-10-04,4003,SUCCESS,All clear
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data /home/user/output
    chmod -R 777 /home/user
