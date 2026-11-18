#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/vuln_app/uploads

    cat << 'EOF' > /home/user/vuln_app/process_upload.sh
#!/bin/bash
UPLOAD_DIR="/home/user/vuln_app/uploads"
INPUT=$1
TARGET=$2

# Flawed path traversal prevention
if [[ "$TARGET" == ../* ]]; then
    echo "Access Denied: Path traversal detected."
    exit 1
fi

cp "$INPUT" "$UPLOAD_DIR/$TARGET"
EOF

    chmod +x /home/user/vuln_app/process_upload.sh

    PASSPHRASE=$(sha256sum /home/user/vuln_app/process_upload.sh | awk '{print $1}')

    cat << 'EOF' > /home/user/vuln_app/db_dump.txt
User: alice, CC: 1111-2222-3333-4444, Role: Admin
User: bob, CC: 5555666677778888, Role: User
User: charlie, CC: 9999-0000-1111-2222, Role: Moderator
User: dave, CC: 1234567812345678, Role: User
EOF

    openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -in /home/user/vuln_app/db_dump.txt -out /home/user/vuln_app/db_dump.enc -pass pass:"$PASSPHRASE"

    rm /home/user/vuln_app/db_dump.txt

    chmod -R 777 /home/user
