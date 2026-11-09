#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest supervisor

    mkdir -p /app/ssh_log_parser /app/corpora/clean /app/corpora/evil /app/incoming_logs

    cat << 'EOF' > /app/ssh_log_parser/parser.py
import re

ALLOWED_KEYS = re.compile(r"ssh-rsa|ssh-dss")

class LogEntry:
    def __init__(self, log_line):
        self.log_line = log_line

    def is_valid(self):
        if ALLOWED_KEYS.search(self.log_line):
            return True
        return False

def check_auth_status(log_line):
    if "Failed password" in log_line or "Invalid" in log_line:
        return False
    return True
EOF

    cat << 'EOF' > /app/corpora/clean/clean_1.log
Accepted publickey for user from 10.0.0.1 port 50000 ssh2: ssh-ed25519 SHA256:...
EOF

    cat << 'EOF' > /app/corpora/clean/clean_2.log
Accepted publickey for user from 10.0.0.2 port 50001 ssh2: ecdsa-sha2-nistp256 SHA256:...
EOF

    cat << 'EOF' > /app/corpora/evil/evil_1.log
Accepted publickey for user from 10.0.0.3 port 50002 ssh2: ssh-dss SHA256:...
EOF

    cat << 'EOF' > /app/corpora/evil/evil_2.log
Failed password for invalid user admin from 10.0.0.4 port 50003 ssh2
Failed password for invalid user root from 10.0.0.4 port 50004 ssh2
EOF

    cat << 'EOF' > /app/corpora/evil/evil_3.log
Accepted publickey for user from 10.0.0.5 port 50005 ssh2: ssh-rsa-malformed SHA256:...
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app/ssh_log_parser /app/corpora /app/incoming_logs
    chmod -R 777 /home/user
