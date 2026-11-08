#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip john
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/shadow_leak.txt
root:$6$xyz123$abcde...:19000:0:99999:7:::
user1:$5$rAnd0m$qWeRtY...:19000:0:99999:7:::
admin_sys:$5$saltsalt$uK.V1R1W/0n0.yRzX.W3eB6o7.q2U8V.8.M.V3.Q/M1:19000:0:99999:7:::
EOF

cat << 'EOF' > /home/user/wordlist.txt
password123
admin
qwerty
s0perS3cret2023!
letmein123
sunshine
EOF

cat << 'EOF' > /home/user/auth_events.json
{"timestamp": "2023-10-25T10:00:00Z", "ip_address": "192.168.1.50", "method": "POST", "endpoint": "/api/login", "request_headers": {"Authorization": "Basic YWRtaW5fc3lzOnBhc3N3b3JkMTIz"}, "response_headers": {}, "status": 401}
{"timestamp": "2023-10-25T10:05:00Z", "ip_address": "10.0.0.99", "method": "POST", "endpoint": "/api/login", "request_headers": {"Authorization": "Basic YWRtaW5fc3lzOnMwcGVyUzNjcmV0MjAyMyE="}, "response_headers": {"Set-Cookie": "session_id=7x9Y2aBcD4eF6gH8; HttpOnly; Secure"}, "status": 200}
{"timestamp": "2023-10-25T10:06:00Z", "ip_address": "10.0.0.99", "method": "GET", "endpoint": "/api/system_data", "request_headers": {"Cookie": "session_id=7x9Y2aBcD4eF6gH8"}, "response_headers": {}, "status": 200}
EOF

chmod -R 777 /home/user
