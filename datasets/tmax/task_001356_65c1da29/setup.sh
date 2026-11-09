#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip systemd tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mailing_list/templates
    mkdir -p /home/user/backups
    mkdir -p /home/user/scripts
    mkdir -p /home/user/.config/systemd/user

    echo "admin_email=admin@example.com" > /home/user/mailing_list/config.cf
    echo "list_name=announcements" >> /home/user/mailing_list/config.cf
    echo "Welcome to the list!" > /home/user/mailing_list/templates/welcome.txt

    cat << 'EOF' > /home/user/scripts/backup_mailer.sh
#!/bin/bash
# Faulty script: relies on relative paths and lacks strict error handling
tar -czf backups/mailer_backup.tar.gz mailing_list/
EOF
    chmod +x /home/user/scripts/backup_mailer.sh

    cat << 'EOF' > /home/user/.config/systemd/user/mailer-backup.service
[Unit]
Description=Mailing List Backup Service

[Service]
Type=oneshot
# Faulty: WorkingDirectory is set to /tmp, causing relative paths to fail or write to /tmp
WorkingDirectory=/tmp
ExecStart=/home/user/scripts/backup_mailer.sh
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
