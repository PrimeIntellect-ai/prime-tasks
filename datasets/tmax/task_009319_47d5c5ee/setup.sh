#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl coreutils gawk tar
pip3 install pytest

mkdir -p /home/user/.ssh
mkdir -p /home/user/system_backup/app
mkdir -p /home/user/exfil_parts
mkdir -p /home/user/recovered_data
mkdir -p /tmp/evidence_staging

cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGoXabc1234567890defghijklmnopqrstuvwxyz12345 admin@corp.local
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILmNopqrstuvwxyz0987654321abcdefghijklmnopqr attacker@evil.com
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbCdEfGhIjKlMnOpQrStUvWxYz01234567890abcdef admin@corp.local
EOF

echo "echo 'System Backup Utility'" > /home/user/system_backup/backup_util
echo "echo 'Good App'" > /home/user/system_backup/app/clean_app
echo "echo 'Rogue Binary Shell'" > /home/user/system_backup/kworker

sha256sum /home/user/system_backup/backup_util > /home/user/known_hashes.txt
sha256sum /home/user/system_backup/app/clean_app >> /home/user/known_hashes.txt

echo "CONFIDENTIAL: Project X Source Code - TOP SECRET" > /tmp/evidence_staging/project_x_intel.txt
tar -czf /tmp/evidence_staging/evidence.tar.gz -C /tmp/evidence_staging project_x_intel.txt

openssl enc -aes-256-cbc -pbkdf2 -salt -in /tmp/evidence_staging/evidence.tar.gz -out /tmp/evidence_staging/encrypted.bin -pass pass:kworker

split -b 50 /tmp/evidence_staging/encrypted.bin /home/user/exfil_parts/part_

sha256sum /tmp/evidence_staging/encrypted.bin | awk '{print $1}' > /home/user/exfil_hash.txt

rm -rf /tmp/evidence_staging

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

# Re-apply SUID bits after the recursive chmod 777
chmod 4755 /home/user/system_backup/backup_util
chmod 4755 /home/user/system_backup/app/clean_app
chmod 4755 /home/user/system_backup/kworker
