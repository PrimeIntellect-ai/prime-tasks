#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/logs.csv
timestamp,user_id,log_message
2023-10-01T10:00:00Z,U105,"System crashed.
ErrorCode: E5001
Stack trace:
line 1
line 2"
2023-10-01T10:05:00Z,U102,"Failed to load asset. ErrorCode: E1042."
2023-10-01T10:10:00Z,U105,"System crashed.
ErrorCode: E5001
Stack trace:
line 1
line 2"
2023-10-01T10:15:00Z,U102,"Connection timeout.
ErrorCode: E2099"
2023-10-01T10:20:00Z,U999,"Garbage log with no error code.
Just multiple lines."
2023-10-01T10:25:00Z,U102,"Failed to load asset. ErrorCode: E1042."
2023-10-01T10:30:00Z,U101,"Unknown issue
ErrorCode: E9999
End of log."
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
