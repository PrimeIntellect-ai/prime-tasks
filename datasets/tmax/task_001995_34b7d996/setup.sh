#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y bubblewrap nodejs iproute2 procps

    # Create user
    useradd -m -s /bin/bash user || true

    # Create dummy.js
    echo "const http = require('http'); http.createServer((req, res) => { res.writeHead(200); res.end('ok'); }).listen(8022);" > /home/user/dummy.js

    # Create traffic.log
    cat << 'EOF' > /home/user/traffic.log
[2023-10-25 14:00:01] 198.51.100.5:54321 -> 127.0.0.1:8010 HTTP_GET /
[2023-10-25 14:00:02] 203.0.113.42:12345 -> 127.0.0.1:8022 HTTP_GET /
[2023-10-25 14:00:03] 198.51.100.5:54322 -> 127.0.0.1:8010 HTTP_GET /
[2023-10-25 14:00:04] 203.0.113.42:12346 -> 127.0.0.1:8022 HTTP_GET /
[2023-10-25 14:00:05] 203.0.113.42:12347 -> 127.0.0.1:8022 HTTP_GET /
[2023-10-25 14:00:06] 10.0.0.5:55555 -> 127.0.0.1:8022 HTTP_GET /
[2023-10-25 14:00:07] 203.0.113.42:12348 -> 127.0.0.1:8022 HTTP_GET /
EOF

    # Set permissions
    chmod -R 777 /home/user
