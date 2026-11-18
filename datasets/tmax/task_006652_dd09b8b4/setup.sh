#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest PyJWT cryptography

    mkdir -p /home/user
    cd /home/user

    # Generate an RSA private key and self-signed certificate
    openssl req -x509 -newkey rsa:2048 -keyout private.pem -out cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=RedTeam/CN=internal-ca-01"

    # Package into PKCS#12 keystore
    openssl pkcs12 -export -out server_keystore.p12 -inkey private.pem -in cert.pem -passout pass:redteam123

    # Clean up intermediate files
    rm private.pem cert.pem

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/server_keystore.p12
    chmod -R 777 /home/user
