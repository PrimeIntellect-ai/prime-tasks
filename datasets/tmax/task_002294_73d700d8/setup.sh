#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ openssl
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/evidence
    mkdir -p /home/user/isolated_env/tmp/

    # Generate a rogue TLS certificate
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/isolated_env/tmp/rogue.key -out /home/user/isolated_env/tmp/rogue.crt -days 365 -nodes -subj "/CN=rogue.admin.local" 2>/dev/null

    # Create the JWT token
    echo -n "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoiYWRtaW4iLCJleGZpbF9wYXRoIjoiL2hvbWUvdXNlci9pc29sYXRlZF9lbnYvdG1wL3JvZ3VlLmNydCJ9." > /home/user/evidence/token.jwt

    # Set permissions
    chown -R user:user /home/user/evidence /home/user/isolated_env
    chmod -R 777 /home/user
