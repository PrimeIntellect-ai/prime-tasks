#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
10.0.0.5 - - [10/Oct/2023:13:55:36 -0000] "GET /login?next=/dashboard HTTP/1.1" 302 150 "-" "Mozilla/5.0" req_001
10.0.0.6 - - [10/Oct/2023:13:55:40 -0000] "GET /login?next=http://evil-domain.com/steal HTTP/1.1" 403 150 "-" "curl/7.68.0" req_002
192.168.5.99 - - [10/Oct/2023:13:56:01 -0000] "GET /login?next=http://evil-domain.com/steal HTTP/1.1" 302 150 "-" "curl/7.68.0" req_003
10.0.0.7 - - [10/Oct/2023:13:56:15 -0000] "GET /login?next=/profile HTTP/1.1" 302 150 "-" "Mozilla/5.0" req_004
EOF

    cat << 'EOF' > /home/user/headers.json
[
  {
    "req_id": "req_001",
    "headers": {
      "User-Agent": "Mozilla/5.0",
      "Cookie": "AuthToken=secure_token_abc; Other=123"
    }
  },
  {
    "req_id": "req_002",
    "headers": {
      "User-Agent": "curl/7.68.0",
      "Cookie": "AuthToken=failed_token_456; UID=88"
    }
  },
  {
    "req_id": "req_003",
    "headers": {
      "User-Agent": "curl/7.68.0",
      "Cookie": "Session=abc; AuthToken=stolen_token_xyz987; UID=99"
    }
  },
  {
    "req_id": "req_004",
    "headers": {
      "User-Agent": "Mozilla/5.0",
      "Cookie": "AuthToken=good_token_111; UID=100"
    }
  }
]
EOF

    cat << 'EOF' > /home/user/policy.json
{
  "firewall_active": true,
  "blocked_ips": [
    "1.2.3.4"
  ]
}
EOF

    chmod -R 777 /home/user
