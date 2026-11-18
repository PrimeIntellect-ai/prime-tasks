#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming_uploads
    mkdir -p /home/user/certs
    mkdir -p /home/user/auth_keys

    echo "OLD_SECRET_123" > /home/user/auth_keys/master_token.txt

    cat << 'EOF' > /home/user/cred_rotator.sh
#!/bin/bash
UPLOAD_DIR="/home/user/incoming_uploads"
CERT_DIR="/home/user/certs"

mkdir -p "$CERT_DIR"

for job in "$UPLOAD_DIR"/*.job; do
    [ -e "$job" ] || continue
    filename=$(cut -d':' -f1 "$job")
    data=$(cut -d':' -f2 "$job")

    echo "$data" | base64 -d > "$CERT_DIR/$filename"
done
EOF

    chmod +x /home/user/cred_rotator.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
