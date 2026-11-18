#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sec_data

    cat << 'EOF' > /home/user/sec_data/auth_logs.json
[
  {
    "id": 1,
    "request": {"headers": {"Authorization": "Bearer abc123def"}},
    "response": {"headers": {"Set-Cookie": "session=xyz; Secure; HttpOnly"}}
  },
  {
    "id": 2,
    "request": {"headers": {"Authorization": "Basic dXNlcjpwYXNz"}},
    "response": {"headers": {"Set-Cookie": "session=abc; Secure; HttpOnly"}}
  },
  {
    "id": 3,
    "request": {"headers": {"Authorization": "Bearer validtoken"}},
    "response": {"headers": {"Set-Cookie": "session=123; HttpOnly"}}
  },
  {
    "id": 4,
    "request": {"headers": {}},
    "response": {"headers": {"Set-Cookie": "session=999; Secure"}}
  },
  {
    "id": 5,
    "request": {"headers": {"Authorization": "Bearer tok"}},
    "response": {"headers": {"Content-Type": "application/json"}}
  }
]
EOF

    cat << 'EOF' > /home/user/sec_data/network_policy.json
[
  {"src_ip_range": "10.0.0.0/8", "dest_port": 80},
  {"src_ip_range": "192.168.1.0/24", "dest_port": 443},
  {"src_ip_range": "172.16.0.0/16", "dest_port": 22}
]
EOF

    cat << 'EOF' > /home/user/sec_data/connections.csv
conn_id,src_ip,dest_port
c1,192.168.1.55,443
c2,192.168.2.55,443
c3,10.5.5.5,80
c4,172.16.10.10,80
c5,172.16.10.10,22
c6,8.8.8.8,443
EOF

    cd /home/user/sec_data
    sha256sum auth_logs.json network_policy.json connections.csv > manifest.sha256

    # INTENTIONALLY MODIFY a file after hashing to trigger a FAIL in integrity
    sed -i 's/Basic/Token/g' auth_logs.json

    chmod -R 777 /home/user
