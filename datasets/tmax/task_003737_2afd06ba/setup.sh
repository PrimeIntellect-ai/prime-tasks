#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl
pip3 install pytest

mkdir -p /home/user/web_certs
cd /home/user/web_certs

# Generate the true matching pair
openssl req -x509 -newkey rsa:2048 -keyout server_true.key -out server.crt -days 365 -nodes -subj "/CN=localhost" 2>/dev/null

# Generate a decoy key
openssl genrsa -out server_decoy.key 2048 2>/dev/null

# Randomly assign true and decoy to alpha/beta
if [ $((RANDOM % 2)) -eq 0 ]; then
    TRUE_BACKUP="backup_alpha.enc"
    DECOY_BACKUP="backup_beta.enc"
else
    TRUE_BACKUP="backup_beta.enc"
    DECOY_BACKUP="backup_alpha.enc"
fi

# Encrypt the keys
openssl enc -aes-256-cbc -salt -in server_true.key -out $TRUE_BACKUP -pass pass:S3cr3tKeyB4ckup -pbkdf2
openssl enc -aes-256-cbc -salt -in server_decoy.key -out $DECOY_BACKUP -pass pass:S3cr3tKeyB4ckup -pbkdf2

# Remove unencrypted keys to force the agent to decrypt
rm server_true.key server_decoy.key

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
