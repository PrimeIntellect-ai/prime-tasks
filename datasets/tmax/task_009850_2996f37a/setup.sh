#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
[2023-10-01T10:00:00Z] 192.168.1.10 "GET /api/v1//data HTTP/1.1" 200 "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "sess_123"
[2023-10-01T10:00:05Z] 10.0.0.5 "POST /auth HTTP/1.0" 401 "curl/7.68.0" "sess_124"
[2023-10-01T10:00:10Z] 192.168.1.10 "GET /api/v1/data HTTP/1.1" 200 "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "sess_123"
[2023-10-01T10:00:15Z] INVALID LOG LINE HERE missing fields
[2023-10-01T10:00:20Z] 172.16.0.2 "GET /images///logo.png HTTP/1.1" 200 "Mozilla/5.0 (X11; Linux x86_64)" "sess_125"
[2023-10-01T10:00:25Z] 192.168.1.11 "GET /index.html HTTP/1.1" 200 "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "sess_126"
EOF

    chmod -R 777 /home/user
