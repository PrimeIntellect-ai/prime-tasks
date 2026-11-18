#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/proxy-resolver

    cat << 'EOF' > /app/proxy-resolver/router.py
import hashlib

def get_socket_path(src_ip, dst_domain):
    # Deliberately broken routing logic
    s = f"{dst_domain}:{src_ip}"
    h = hashlib.md5(s.encode()).hexdigest()
    val = int(h[-2:], 16)
    idx = val % 5
    return f"/tmp/upstream_{idx}.sock"
EOF

    cat << 'EOF' > /app/proxy-resolver/resolver.py
#!/usr/bin/env python3
import sys
from router import get_socket_path

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) == 2:
            print(get_socket_path(parts[0], parts[1]))

if __name__ == "__main__":
    main()
EOF

    chmod +x /app/proxy-resolver/resolver.py

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/resolver_oracle.py
#!/usr/bin/env python3
import sys
import hashlib

def get_socket_path(src_ip, dst_domain):
    s = f"{src_ip}:{dst_domain}"
    h = hashlib.md5(s.encode()).hexdigest()
    val = int(h[-2:], 16)
    idx = val % 4
    return f"/var/run/upstream_{idx}.sock"

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) == 2:
            print(get_socket_path(parts[0], parts[1]))

if __name__ == "__main__":
    main()
EOF

    chmod +x /opt/oracle/resolver_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
