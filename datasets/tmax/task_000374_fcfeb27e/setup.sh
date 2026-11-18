#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_access.log
192.168.1.1 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
10.0.0.2 - - [10/Oct/2023:13:55:37 -0700] "POST /login.php?user=admin&pass=123 HTTP/1.1" 401 532
172.16.0.5 - - [10/Oct/2023:13:55:38 -0700] "GET /search?q=<script>alert(1)</script> HTTP/1.1" 403 1024
192.168.1.100 - - [10/Oct/2023:13:55:39 -0700] "GET /api/data?id=1&token=base64_encoded_str HTTP/1.1" 200 89
10.0.0.8 - - [10/Oct/2023:13:55:40 -0700] "PUT /upload/test.txt HTTP/1.1" 201 0
EOF

    chmod -R 777 /home/user
