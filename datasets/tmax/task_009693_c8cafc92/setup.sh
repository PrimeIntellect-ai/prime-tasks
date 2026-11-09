#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/raw
    cat << 'EOF' > /home/user/raw/server1.csv
IP,Date,Endpoint,Status,UserAgent
192.168.1.1,2023-10-01,/api/users,200,Mozilla
192.168.1.2,2023-10-01,/api/auth,401,Chrome
192.168.1.3,2023-10-01,/api/data,500,Curl
192.168.1.4,2023-10-01,/api/users,201,Safari
192.168.1.5,2023-10-01,/api/users,502,Firefox
EOF

    cat << 'EOF' > /home/user/raw/server2.csv
Date,IP,Status,Endpoint,ResponseTime
2023-10-02,10.0.0.1,200,/api/auth,120
2023-10-02,10.0.0.2,404,/api/data,45
2023-10-02,10.0.0.3,200,/api/users,300
2023-10-02,10.0.0.4,500,/api/auth,900
EOF

    cat << 'EOF' > /home/user/raw/server3.csv
Endpoint,Date,IP,UserAgent,Status
/api/data,2023-10-03,172.16.0.1,Chrome,200
/api/data,2023-10-03,172.16.0.2,Firefox,200
/api/auth,2023-10-03,172.16.0.3,Safari,403
/api/users,2023-10-03,172.16.0.4,Curl,503
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/raw
    chmod -R 777 /home/user
