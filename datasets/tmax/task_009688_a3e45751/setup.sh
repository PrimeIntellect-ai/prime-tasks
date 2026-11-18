#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/traffic_logs.json
[
  {
    "source_ip": "192.168.1.50",
    "method": "GET",
    "url": "/dashboard",
    "headers": {
      "User-Agent": "Mozilla/5.0",
      "Cookie": "uid=12; session_data=ZWFzdGVyX2VnZ19ub3RoaW5nX2hlcmU=; theme=light",
      "X-Test-WAF": "false"
    }
  },
  {
    "source_ip": "10.0.0.99",
    "method": "POST",
    "url": "/login",
    "headers": {
      "User-Agent": "curl/7.68.0",
      "Cookie": "session_data=PHNjcmlwdD5hbGVydCgnWFNTIEJ5cGFzcycpPC9zY3JpcHQ+; uid=999",
      "X-Test-WAF": "true"
    }
  },
  {
    "source_ip": "172.16.0.4",
    "method": "GET",
    "url": "/profile",
    "headers": {
      "User-Agent": "Mozilla/5.0",
      "Cookie": "theme=dark; session_data=anVzdF9zb21lX2Jlbmlnbl9kYXRh",
      "X-Test-WAF": "true"
    }
  }
]
EOF

    chmod -R 777 /home/user
