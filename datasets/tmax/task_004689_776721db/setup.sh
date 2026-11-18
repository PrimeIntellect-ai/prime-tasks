#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input_logs.txt
[2023-10-01T10:00:00] 192.168.1.1 404 PageNotFound
[2023-10-01T10:00:01] 10.0.0.2 500 InternalServerError
[2023-10-01T10:00:02] 192.168.1.1 404 PageNotFound
[2023-10-01T10:00:03] 172.16.0.1 500 DatabaseTimeout
[2023-10-01T10:00:04] 10.0.0.3 500 InternalServerError
[2023-10-01T10:00:05] 192.168.1.5 503 ServiceUnavailable
[2023-10-01T10:00:06] 192.168.1.6 404 MissingImage
[2023-10-01T10:00:07] 192.168.1.7 404 MissingCSS
[2023-10-01T10:00:08] 192.168.1.8 200 OK
[2023-10-01T10:00:09] 192.168.1.9 503 ServiceUnavailable
[2023-10-01T10:00:10] 192.168.1.10 503 GatewayTimeout
[2023-10-01T10:00:11] 192.168.1.11 503 NodeFailure
[2023-10-01T10:00:12] 10.0.0.1 500 DiskFull
EOF

    chmod -R 777 /home/user
