#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_logs.txt
[2023-10-01T10:00:01Z] | 192.168.1.100 | 200 | eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
[2023-10-01T10:05:12Z] | 203.0.113.45 | 401 | eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhZG1pbiJ9.
[2023-10-01T10:12:33Z] | 198.51.100.22 | 200 | eyJhbGciOiJub25lIn0=.eyJyb2xlIjoiYWRtaW4iLCJ1c2VyIjoiYm9iIn0=.
[2023-10-01T10:15:44Z] | 10.0.0.5 | 200 | eyJhbGciOiJIUzI1NiJ9.eyJuYW1lIjoiYWxpY2UifQ.abcdef123456
[2023-10-01T10:20:01Z] | 203.0.113.99 | 200 | eyJhbGciOiAibm9uZSJ9.eyJzdWIiOiJzeXNhZG1pbiJ9.
EOF

    chmod -R 777 /home/user
