#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
[2023-10-01T10:00:00] [192.168.1.100] [INFO] User logged in with CC 1234-5678-9012-3456
[2023-10-01T10:01:00] [10.0.0.5] [WARN] Failed login attempt ' OR '1'='1 --
[2023-10-01T10:02:00] [10.0.0.5] [WARN] Search query: <script>alert(1)</script>
[2023-10-01T10:03:00] [192.168.1.101] [DEBUG] Auth failed: hash=5f4dcc3b5aa765d61d8327deb882cf99
[2023-10-01T10:04:00] [10.0.0.5] [WARN] GET /admin?id=1' Or '1'='1
[2023-10-01T10:05:00] [192.168.1.102] [DEBUG] Auth failed: hash=098f6bcd4621d373cade4e832627b4f6
[2023-10-01T10:06:00] [192.168.1.103] [INFO] Payment processed for 9876-5432-1098-7654
[2023-10-01T10:07:00] [192.168.1.200] [WARN] Comment: Nice post!
[2023-10-01T10:08:00] [172.16.0.4] [WARN] Input: <sCript>steal()</script>
EOF

    cat << 'EOF' > /home/user/wordlist.txt
admin
password
123456
test
qwerty
letmein
security
EOF

    chmod -R 777 /home/user
