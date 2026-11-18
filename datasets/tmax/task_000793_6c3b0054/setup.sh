#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_logs/subdir

    cat << 'EOF' > /home/user/backup_config.json
{
  "target_dir": "/home/user/app_logs",
  "min_days_old": 5,
  "mask_regex": "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b",
  "mask_replacement": "[REDACTED_EMAIL]",
  "archive_path": "/home/user/secure_backup.zip"
}
EOF

    cat << 'EOF' > /home/user/app_logs/log1.txt
User admin@example.com logged in.
Error from user123@test.co.uk: timeout.
EOF

    cat << 'EOF' > /home/user/app_logs/subdir/log2.txt
Contact us at support@domain.com.
System ok.
EOF

    cat << 'EOF' > /home/user/app_logs/log3_new.txt
New user hello@world.com signed up.
EOF

    touch -d "10 days ago" /home/user/app_logs/log1.txt
    touch -d "7 days ago" /home/user/app_logs/subdir/log2.txt
    touch -d "1 day ago" /home/user/app_logs/log3_new.txt

    chmod -R 777 /home/user
