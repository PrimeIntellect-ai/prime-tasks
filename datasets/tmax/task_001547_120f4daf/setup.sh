#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.log
192.168.1.50 - [12/Oct/2023:10:00:01 +0000] "GET /login?user=alice&password=MyPassword1&redirect_url=/dashboard HTTP/1.1" 200
203.0.113.42 - [12/Oct/2023:10:05:12 +0000] "GET /login?user=bob&password=hunter2&redirect_url=https://evil-phishing.com/login HTTP/1.1" 302
192.168.1.51 - [12/Oct/2023:10:10:00 +0000] "GET /login?user=charlie&password=qwerty&redirect_url=https://internal.company.local/settings HTTP/1.1" 200
198.51.100.7 - [12/Oct/2023:10:15:33 +0000] "GET /login?user=admin&password=admin&redirect_url=http://malicious.site.net/payload HTTP/1.1" 302
203.0.113.42 - [12/Oct/2023:10:20:00 +0000] "GET /login?user=dave&password=12345&redirect_url=https://attacker.com/drop HTTP/1.1" 302
EOF

    chmod -R 777 /home/user
