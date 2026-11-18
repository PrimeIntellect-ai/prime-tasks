#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest aiosmtpd

# Create directories
mkdir -p /home/user/legacy_logs /home/user/migration /home/user/app_data /home/user/backups

# Create legacy log file
cat << 'EOF' > /home/user/legacy_logs/app.log
2023-10-12 14:20:01 [INFO] Service started
2023-10-12 14:21:12 [CRITICAL] Database connection timeout
2023-10-12 14:22:05 [WARN] Memory usage high
2023-10-12 14:22:11 [CRITICAL] Cache server unreachable
2023-10-12 14:23:00 [CRITICAL] Network partition detected
2023-10-12 14:24:15 [INFO] User login success
2023-10-12 14:25:01 [CRITICAL] File system read-only
2023-10-12 14:26:00 [CRITICAL] Process crashed unexpectedly
2023-10-12 14:27:00 [CRITICAL] Disk space 99% full
EOF

# Create dummy app data
echo "dummy data 1" > /home/user/app_data/config.json
echo "dummy data 2" > /home/user/app_data/users.db

# Create old dummy backups to test rotation (manipulate mtime to ensure they are older)
touch -t 202310010000 /home/user/backups/backup_20231001_000000.tar.gz
touch -t 202310020000 /home/user/backups/backup_20231002_000000.tar.gz
touch -t 202310030000 /home/user/backups/backup_20231003_000000.tar.gz

# Start a mock SMTP server to capture the email output
cat << 'EOF' > /home/user/migration/mock_smtp.py
import asyncio
from aiosmtpd.controller import Controller

class CustomHandler:
    async def handle_DATA(self, server, session, envelope):
        with open("/home/user/migration/sent_emails.log", "a") as f:
            f.write(envelope.content.decode('utf8', errors='replace'))
        return '250 Message accepted for delivery'

if __name__ == '__main__':
    handler = CustomHandler()
    controller = Controller(handler, hostname='127.0.0.1', port=8025)
    controller.start()
    input() # Keep alive
EOF

# Create the user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
