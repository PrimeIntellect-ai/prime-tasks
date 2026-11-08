#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas chardet python-dateutil

    mkdir -p /home/user/raw_data/
    mkdir -p /home/user/db/

    # Create File 1 (UTF-8)
    cat << 'EOF' > /home/user/raw_data/file1.csv
Date,Temp,Metadata
2023-10-01 10:00:00,22.5,device_id=S1; battery=90
2023-10-01 10:05:00,22.7,device_id=S1; battery=89
EOF

    # Create File 2 (UTF-16LE)
    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > /home/user/raw_data/file2.csv
Timestamp,Temperature,Info
10/01/2023 10:00 AM,23.1,device_id: S2 | battery: 85
10/01/2023 10:05 AM,23.2,device_id: S2 | battery: 84
EOF

    # Create File 3 (ISO-8859-1) - Overlaps with File 1
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/raw_data/file3.csv
Time,Temp,Meta
2023-10-01T10:00:00Z,22.5,device_id=S1; battery=90
2023-10-01T10:10:00Z,22.9,device_id=S1; battery=88
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/raw_data/ /home/user/db/
    chmod -R 777 /home/user
