#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest

    mkdir -p /app/bin /app/corpora/clean /app/corpora/evil

    # Create dummy binary
    touch /app/bin/log_decoder
    chmod +x /app/bin/log_decoder

    # Populate clean corpus
    echo "GET /index.html HTTP/1.1" > /app/corpora/clean/1.txt
    echo "POST /login HTTP/1.1" > /app/corpora/clean/2.txt

    # Populate evil corpus
    echo "GET /search?q=<script>alert(1);</script> HTTP/1.1" > /app/corpora/evil/1.txt
    echo "ERROR: Client cert failed: -----BEGIN PRIVATE KEY-----MIIEpQIBAAKCAQEA-----END PRIVATE KEY-----" > /app/corpora/evil/2.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
