#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/server.log
{"time":"2023-10-01T09:12:00Z", "ip":"10.0.0.5", "method":"GET", "path":"/index.html", "status":200, "session_id":"anon123"}
{"time":"2023-10-01T09:15:00Z", "ip":"192.168.1.105", "method":"GET", "path":"/admin/secret_config.json", "status":403, "session_id":"guest888"}
{"time":"2023-10-01T09:16:00Z", "ip":"192.168.1.105", "method":"GET", "path":"/admin/secret_config.json", "status":403, "session_id":"guest888"}
{"time":"2023-10-01T09:17:00Z", "ip":"172.16.0.4", "method":"GET", "path":"/about", "status":200, "session_id":"anon444"}
{"time":"2023-10-01T09:18:00Z", "ip":"192.168.1.105", "method":"GET", "path":"/admin/secret_config.json", "status":200, "session_id":"s3cr3tsalt"}
{"time":"2023-10-01T09:20:00Z", "ip":"10.0.0.5", "method":"GET", "path":"/contact", "status":200, "session_id":"anon123"}
EOF

    cat << 'EOF' > /home/user/wordlist.txt
password123
admin
admin123
qwerty
cyberdragon
letmein
dragon
p@ssword
EOF

    cat << 'EOF' > /home/user/shadow.txt
admin:19c3c13ff0358bdcf31502da55702280d97b0a7c413da6f1ec28fcfaf48af2de
EOF

    chmod -R 777 /home/user
