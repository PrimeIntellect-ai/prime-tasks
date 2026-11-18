#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core openssl tar
pip3 install pytest

mkdir -p /app

# Generate image
convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'SuperSecretAdmin2024!'" /app/legacy_passphrase.png

# Create fake logs
cat << 'EOF' > /tmp/server.log
2024-01-01 10:00:00 INFO [main] Login attempt: https://example.com/login?username=admin&password=Password123&action=login
2024-01-01 10:05:00 WARN [auth] Failed token validation: {"user": "test", "session_token": "abc123xyz", "ip": "10.0.0.1"}
2024-01-01 10:10:00 INFO [api] Data sync secret_key=9876543210
2024-01-01 10:15:00 INFO [main] Normal log entry with no secrets.
EOF

# Encrypt logs
tar -cf /tmp/logs.tar -C /tmp server.log
openssl enc -aes-256-cbc -pbkdf2 -salt -in /tmp/logs.tar -out /app/encrypted_logs.tar.enc -pass pass:'SuperSecretAdmin2024!'

# Create expected output for verification
cat << 'EOF' > /app/expected_clean.log
2024-01-01 10:00:00 INFO [main] Login attempt: https://example.com/login?username=admin&password=[REDACTED]&action=login
2024-01-01 10:05:00 WARN [auth] Failed token validation: {"user": "test", "session_token": "[REDACTED]", "ip": "10.0.0.1"}
2024-01-01 10:10:00 INFO [api] Data sync secret_key=[REDACTED]
2024-01-01 10:15:00 INFO [main] Normal log entry with no secrets.
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
