#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl faketime
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/headers.json
{
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  "X-Content-Type-Options": "nosniff",
  "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline'; object-src 'none'",
  "Content-Type": "text/html; charset=utf-8"
}
EOF

    faketime '2010-01-01 00:00:00' openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /home/user/cert.pem -days 365 -nodes -subj "/C=US/ST=CA/L=SF/O=Test/CN=localhost" -sha1

    chown -R user:user /home/user
    chmod -R 777 /home/user
