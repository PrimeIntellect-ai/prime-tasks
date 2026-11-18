#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx openssl imagemagick fonts-dejavu-core
    pip3 install pytest

    # Create certificates
    mkdir -p /app/certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /app/certs/server.key -out /app/certs/server.crt \
        -subj "/CN=localhost"

    # Generate architecture config image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 10,30 'UPSTREAM_PORT=9090'" \
        -draw "text 10,60 'TLS_CERTS_DIR=/app/certs/'" \
        /app/arch_config.png

    # Create corpus directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Add clean files
    cat << 'EOF' > /app/corpus/clean/clean_1.txt
GET /api/status HTTP/1.1
Host: localhost

EOF

    cat << 'EOF' > /app/corpus/clean/clean_2.txt
POST /api/data HTTP/1.1
Host: localhost
Content-Type: application/json
Content-Length: 15

{"user":"test"}
EOF

    # Add evil files
    cat << 'EOF' > /app/corpus/evil/evil_1.txt
GET /api/v1/../../etc/passwd HTTP/1.1
Host: localhost

EOF

    cat << 'EOF' > /app/corpus/evil/evil_2.txt
GET /search?q=UNION+SELECT+* HTTP/1.1
Host: localhost

EOF

    cat << 'EOF' > /app/corpus/evil/evil_3.txt
POST /submit HTTP/1.1
Host: localhost
Content-Type: text/plain
Content-Length: 25

<script>alert(1)</script>
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /app/
    chmod -R 777 /home/user
