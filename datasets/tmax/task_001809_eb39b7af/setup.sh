#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
10.0.0.1 - - [01/Nov/2023:10:00:00 +0000] "GET / HTTP/1.1" 403 153 "-" "Mozilla/5.0" "Cookie: session=PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg=="
10.0.0.1 - - [01/Nov/2023:10:05:00 +0000] "GET / HTTP/1.1" 403 153 "-" "Mozilla/5.0" "Cookie: session=JTNDc2NyaXB0JTNFYWxlcnQlMjgxJTI5JTNDJTJGc2NyaXB0JTNF"
10.0.0.1 - - [01/Nov/2023:10:10:00 +0000] "GET / HTTP/1.1" 200 2048 "-" "Mozilla/5.0" "Cookie: session=PnRwaXJjcy88PjEodHJlbGE+dHBpcmNzPA=="
10.0.0.1 - - [01/Nov/2023:10:15:00 +0000] "GET / HTTP/1.1" 403 153 "-" "Mozilla/5.0" "Cookie: session=PHN2ZyBvbmxvYWQ9cHJvbXB0KDEpPg=="
EOF

    chmod 644 /home/user/access.log
    chmod -R 777 /home/user
