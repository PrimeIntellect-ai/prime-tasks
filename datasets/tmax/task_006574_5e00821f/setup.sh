#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/servers.csv
ServerID,Region,IPAddress,OwnerEmail
S1,US-East,10.0.0.15,admin1@company.com
S2,EU-West,192.168.100.22,sysop_eu@company.com
S3,US-West,172.16.5.99,devops@internal.net
EOF

    cat << 'EOF' > /home/user/changes.csv
ServerID,Timestamp,UserID,ConfigKey,NewValue
S1,2023-10-01T10:00:00Z,U98765,MaxConnections,100
S2,2023-10-01T11:00:00Z,U12345,Timeout,30
S1,2023-10-02T09:00:00Z,U98765,Port,8080
S3,2023-10-03T08:15:00Z,A0001Z,LogLevel,DEBUG
S2,2023-10-04T14:20:00Z,U12345,SSL,true
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
