#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/api_requests.log
[2023-10-25 10:00:00] IP: 10.0.0.5 Method: GET Path: /data Auth: Bearer sk_live_goodKey123 Status: 200
[2023-10-25 10:01:00] IP: 198.51.100.45 Method: POST Path: /admin Auth: Bearer sk_live_maliciousKey1 Status: 403
[2023-10-25 10:02:00] IP: 192.168.1.50 Method: GET Path: /users Auth: Bearer sk_live_anotherGoodKey Status: 200
[2023-10-25 10:05:00] IP: 198.51.100.200 Method: GET Path: /billing Auth: Bearer sk_live_hackedKey2 Status: 200
[2023-10-25 10:10:00] IP: 198.51.100.45 Method: DELETE Path: /admin Auth: Bearer sk_live_maliciousKey1 Status: 200
EOF

    chown user:user /home/user/api_requests.log
    chmod -R 777 /home/user
