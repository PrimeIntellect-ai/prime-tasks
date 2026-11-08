#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip
    pip3 install pytest setuptools

    mkdir -p /app/ssh_log_analyzer-1.0.0/ssh_log_analyzer

    cat << 'EOF' > /app/ssh_log_analyzer-1.0.0/setup.py
from setuptools import setup, find_packages
setup(
    name='ssh_log_analyzer',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/ssh_log_analyzer-1.0.0/ssh_log_analyzer/__init__.py
from .parser import parse_log_line
EOF

    cat << 'EOF' > /app/ssh_log_analyzer-1.0.0/ssh_log_analyzer/parser.py
import re

IP_REGEX = r"(\d{1,3}\.){3}\d{1,3}"
KEY_REGEX = r"RSA ([0-9a-f:]+)"

def parse_log_line(line):
    ip_match = re.search(IP_REGEX, line)
    key_match = re.search(KEY_REGEX, line)

    if ip_match and key_match:
        return {
            "ip": ip_match.group(0),
            "key_fingerprint": key_match.group(0)
        }
    return None
EOF

    cd /app
    tar -czf ssh_log_analyzer-1.0.0.tar.gz ssh_log_analyzer-1.0.0/
    rm -rf ssh_log_analyzer-1.0.0/

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth.log
Jan 01 12:00:00 host sshd[1234]: Accepted publickey for user from 10.0.0.5 port 12345 ssh2: ED25519 SHA256:p2QAMXGrxoQzK+wM6fK+f9c/8M1e3k6H/9l2A1C3E4Q
Jan 01 12:01:00 host sshd[1235]: Accepted publickey for user from 192.168.50.2 port 12346 ssh2: RSA MD5:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff:00
Jan 01 12:02:00 host sshd[1236]: Accepted publickey for user from 2001:db8::ff00:42:8329 port 12347 ssh2: ED25519 SHA256:p2QAMXGrxoQzK+wM6fK+f9c/8M1e3k6H/9l2A1C3E4Q
Jan 01 12:03:00 host sshd[1237]: Accepted publickey for user from 10.1.1.1 port 12348 ssh2: RSA SHA256:abcd
EOF

    cat << 'EOF' > /home/user/cwe_rules.json
{
  "weak_keys": [
    "SHA256:p2QAMXGrxoQzK+wM6fK+f9c/8M1e3k6H/9l2A1C3E4Q",
    "MD5:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff:00"
  ]
}
EOF

    chmod -R 777 /home/user
