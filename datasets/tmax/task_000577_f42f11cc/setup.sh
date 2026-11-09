#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/firewall.json
{
  "outbound": [
    {"ip": "10.0.0.5", "port": 80, "action": "ALLOW"},
    {"ip": "192.168.1.50", "port": 443, "action": "DENY"},
    {"ip": "172.16.0.5", "port": 80, "action": "ALLOW"},
    {"ip": "10.0.1.10", "port": 443, "action": "ALLOW"}
  ]
}
EOF

    cat << 'EOF' > /home/user/csp.txt
Content-Security-Policy: default-src 'none'; img-src https://images.trusted.com http://metrics.trusted.com https://log.trusted.com; script-src 'self'
EOF

    cat << 'EOF' > /home/user/dns.txt
images.trusted.com 192.168.1.50
metrics.trusted.com 10.0.0.5
log.trusted.com 10.0.1.99
EOF

    cat << 'EOF' > /home/user/waf_rules.txt
fetch
XMLHttpRequest
document.cookie
eval
setTimeout
EOF

    chmod -R 777 /home/user
