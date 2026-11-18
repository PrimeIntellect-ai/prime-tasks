#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs /home/user/compromised

    cat << 'EOF' > /home/user/compromised/shell.py
import os; os.system('/bin/bash')
EOF

    cat << 'EOF' > /home/user/logs/web.log
10.0.0.5 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 - "Cookie: session=user99"
192.168.1.100 - - [10/Oct/2023:13:56:01 -0700] "GET /search?q=<script>alert(1)</script> HTTP/1.1" 403 - "Cookie: session=guest"
192.168.137.42 - - [10/Oct/2023:14:01:12 -0700] "GET /search?q=<SCRIPT>document.cookie</SCRIPT> HTTP/1.1" 403 - "Cookie: session=admin_super_secret_992"
192.168.137.42 - - [10/Oct/2023:14:02:45 -0700] "GET /profile?user=javascript:alert(1) HTTP/1.1" 403 - "Cookie: session=admin_super_secret_992"
10.0.0.5 - - [10/Oct/2023:14:03:00 -0700] "POST /upload?dir=images&filename=cat.png HTTP/1.1" 200 - "Cookie: session=user99"
192.168.137.42 - - [10/Oct/2023:14:05:10 -0700] "POST /upload?dir=../../compromised/&filename=shell.py HTTP/1.1" 200 - "Cookie: session=admin_super_secret_992"
192.168.137.42 - - [10/Oct/2023:14:06:00 -0700] "GET /compromised/shell.py HTTP/1.1" 200 - "Cookie: session=admin_super_secret_992"
EOF

    chmod -R 777 /home/user
