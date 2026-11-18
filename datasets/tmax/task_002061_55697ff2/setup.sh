#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.csv
id,ts,level,msg
1,1696154400,INFO,System started normally at 192.168.1.10
2,1696154460,ERROR,Connection timeout to database
3,2023-10-01T10:05:00Z,ERROR,Failed to parse token a1b2c3d4
4,1696155000,ERROR,Disk space low on 10.0.0.5
5,1696156000,INFO,User login successful
6,1696157900,ERROR,Memory out of bounds
2,1696154470,ERROR,Connection timeout to database (retry)
7,2023-10-01T11:30:00Z,ERROR,Network unreadable at 172.16.0.1
8,1696158100,ERROR,Null pointer exception in module f9e8d7
9,1696161600,ERROR,API rate limit exceeded
10,1696161650,ERROR,API rate limit exceeded
11,1696161700,ERROR,API rate limit exceeded
12,2023-10-01T12:10:00Z,ERROR,API rate limit exceeded from 192.168.1.50
13,1696162000,ERROR,Database locked by process cdef123
14,1696162100,ERROR,Write failure
15,1696162200,ERROR,Read failure
3,1696153500,ERROR,Failed to parse token a1b2c3d4 (initial attempt)
16,1696165200,ERROR,Minor warning escalated to error
17,1696165300,INFO,Health check passed
EOF

    chmod -R 777 /home/user
