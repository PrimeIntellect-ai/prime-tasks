#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk file
    pip3 install pytest

    mkdir -p /home/user/remote_stash
    mkdir -p /home/user/setup_temp
    cd /home/user/setup_temp

    # Create server1.csv (UTF-8, normal)
    cat << 'EOF' > server1.csv
server_id,change_id,status,description,timestamp
srv1,c001,APPLIED,"Update nginx workers",2023-01-01T10:00:00Z
srv1,c002,REJECTED,"Invalid port 99999",2023-01-01T10:05:00Z
srv1,c003,APPLIED,"Restart service",2023-01-01T10:10:00Z
EOF

    # Create server2.csv (UTF-16LE, embedded newlines)
    cat << 'EOF' > server2_utf8.csv
server_id,change_id,status,description,timestamp
srv2,c101,APPLIED,"Set max_memory",2023-01-02T11:00:00Z
srv2,c102,REJECTED,"Missing closing bracket
in config file
line 42",2023-01-02T11:05:00Z
srv2,c103,REJECTED,"User 'admin'
does not exist",2023-01-02T11:10:00Z
EOF
    iconv -f UTF-8 -t UTF-16LE server2_utf8.csv > server2.csv
    rm server2_utf8.csv

    # Create server3.csv (UTF-8, embedded newlines)
    cat << 'EOF' > server3.csv
server_id,change_id,status,description,timestamp
srv3,c201,REJECTED,"Syntax error
unknown directive 'fasthttps'",2023-01-03T12:00:00Z
srv3,c202,APPLIED,"Rollback",2023-01-03T12:15:00Z
EOF

    tar -czf /home/user/remote_stash/configs.tar.gz server1.csv server2.csv server3.csv
    cd /home/user
    rm -rf /home/user/setup_temp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
