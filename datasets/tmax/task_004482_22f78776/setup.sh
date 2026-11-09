#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
10.0.0.15 - - [14/Nov/2023:08:12:01 +0000] "GET /index.html HTTP/1.1" 200 1024
10.0.0.15 - - [14/Nov/2023:08:12:05 +0000] "GET /style.css HTTP/1.1" 200 451
192.168.1.42 - - [14/Nov/2023:09:41:10 +0000] "GET /products?id=1' HTTP/1.1" 500 230
192.168.1.42 - - [14/Nov/2023:09:41:15 +0000] "GET /products?id=1'%20OR%201=1-- HTTP/1.1" 200 5021
192.168.1.42 - - [14/Nov/2023:09:42:01 +0000] "GET /products?id=1'%20UNION%20SELECT%20id,name,email,ssn,cc_number%20FROM%20users-- HTTP/1.1" 200 8943
172.16.0.5 - - [14/Nov/2023:10:05:00 +0000] "GET /contact HTTP/1.1" 200 890
EOF

    cat << 'EOF' > /home/user/compromised_db_dump.csv
id,name,email,ssn,cc_number
1,Alice Smith,alice@example.com,123-45-6789,4111-2222-3333-4444
2,Bob Jones,bob@example.com,987-65-4321,5555-6666-7777-8888
3,Charlie Brown,charlie@example.com,555-00-1234,3400-1234-5678-9012
EOF

    chmod -R 777 /home/user
