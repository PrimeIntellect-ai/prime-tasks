#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/requests.log
192.168.1.1,/api/login
192.168.1.1,/api/data
10.0.0.2,/home/index.html
192.168.1.1,/api/logout
192.168.1.1,/api/info
10.0.0.2,/api/test
malformed_line_no_comma
10.0.0.3,/api/v1/ping
10.0.0.2,/api/status
10.0.0.2,/api/query
EOF

    chmod -R 777 /home/user
