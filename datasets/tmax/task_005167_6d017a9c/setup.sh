#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat curl coreutils
    pip3 install pytest

    mkdir -p /app/bash-serve-config
    mkdir -p /home/user

    # Use base64 to avoid Apptainer template variable syntax errors with braces
    echo "IyEvYmluL2Jhc2gKIyBQZXJ0dXJiYXRpb246IEJyb2tlbiBncmVlZHkgcmVnZXggZm9yIGludGVycG9sYXRpb24KIyBFeHBlY3RzIGEgc3RyZWFtIGFuZCBhbiBlbnYgZmlsZSBwYXRoIGFzIGFyZyAkMQpzb3VyY2UgIiQxIiAyPi9kZXYvbnVsbAojIEdyZWVkeSBtYXRjaCBidWc6CndoaWxlIElGUz0gcmVhZCAtciBsaW5lOyBkbwogICAgZWNobyAiJGxpbmUiIHwgc2VkIC1FICdzL1x7XHsuKlx9XH0vQlJPS0VOL2cnCmRvbmUK" | base64 -d > /app/bash-serve-config/interpolate.sh
    chmod +x /app/bash-serve-config/interpolate.sh

    cat << 'EOF' > /app/bash-serve-config/server.sh
#!/bin/bash
# Perturbation: Ignores the $PORT env var
LISTEN_PORT=9999
FILE_TO_SERVE=$1
socat TCP-LISTEN:${LISTEN_PORT},bind=127.0.0.1,reuseaddr,fork SYSTEM:"echo HTTP/1.1 200 OK; echo Content-Type\: application/json; echo; cat ${FILE_TO_SERVE}"
EOF
    chmod +x /app/bash-serve-config/server.sh

    cat << 'EOF' > /home/user/vars.env
DB_HOST=db.example.com
DB_PORT=5432
API_KEY=secret_123
EOF

    # Use base64 to avoid Apptainer template variable syntax errors with braces
    echo "ewogICJkYXRhYmFzZSI6ICJwb3N0Z3Jlc3FsOi8ve3sgREJfSE9TVCB9fTp7eyBEQl9QT1JUIH19L215ZGIiLAogICJhdXRoIjogewogICAgImtleSI6ICJ7eyBBUElfS0VZIH19IiwKICAgICJyZWdpb24iOiAie3sgUkVHSU9OIH19IgogIH0KfQo=" | base64 -d > /home/user/config.template.json

    useradd -m -s /bin/bash user || true
    chown -R user:user /app/bash-serve-config /home/user
    chmod -R 777 /home/user
