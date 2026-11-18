#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
pip3 install pytest

# Create directories
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Generate the voicemail audio file
espeak -w /app/voicemail.wav "Alert. Rogue queries detected. Sanitize all backups referencing the table omega_vault_credentials. I repeat, drop any query containing omega_vault_credentials."

# Generate 20 clean SQL files
for i in $(seq 1 25); do
cat <<EOF > /app/corpus/clean/clean_$i.sql
SELECT u.id, u.username, p.profile_data
FROM users u
JOIN user_profiles p ON u.id = p.user_id
WHERE u.status = 'active' AND u.login_count > $i;
EOF
done

# Generate 20 evil SQL files containing the sensitive table name
for i in $(seq 1 25); do
cat <<EOF > /app/corpus/evil/evil_$i.sql
SELECT u.id, u.username, o.password_hash
FROM users u
JOIN omega_vault_credentials o ON u.id = o.user_id
WHERE u.status = 'active' AND u.login_count > $i;
EOF
done

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
