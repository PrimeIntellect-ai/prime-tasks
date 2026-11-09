#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq expect curl
pip3 install pytest

mkdir -p /home/user/bin
mkdir -p /home/user/staging
mkdir -p /home/user/prod

cat << 'EOF' > /home/user/bin/legacy_billing
#!/usr/bin/env bash
read -p "Username: " user
read -s -p "Password: " pass
echo ""
if [[ "$user" == "finops" && "$pass" == "CostCut2024!" ]]; then
    echo '{"status": "success", "total_cost": 4250.75, "currency": "USD"}'
else
    echo '{"status": "error", "message": "Authentication failed"}'
    exit 1
fi
EOF
chmod +x /home/user/bin/legacy_billing

cat << 'EOF' > /home/user/bin/mock_smtp.py
import smtpd
import asyncore
import os

class CustomSMTPServer(smtpd.SMTPServer):
    def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
        with open("/home/user/mail.log", "a") as f:
            f.write(f"FROM: {mailfrom}\n")
            f.write(f"TO: {rcpttos}\n")
            f.write(f"DATA:\n{data.decode('utf-8')}\n---\n")

server = CustomSMTPServer(('127.0.0.1', 1025), None)
asyncore.loop()
EOF

python3 /home/user/bin/mock_smtp.py &
echo $! > /home/user/bin/smtp.pid

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
