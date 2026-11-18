#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl tar openssl
    pip3 install pytest cryptography

    mkdir -p /app/bin /app/vendor /app/corpora/evil /app/corpora/clean

    # Generate old key pair
    openssl genrsa -out /tmp/old_key.pem 2048
    openssl rsa -in /tmp/old_key.pem -pubout -out /tmp/old_pub.pem

    # Create legacy binary with embedded public key
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
const char* pub_key = 
EOF
    sed 's/^/"/; s/$/\\n"/' /tmp/old_pub.pem >> /tmp/legacy.c
    echo ";" >> /tmp/legacy.c
    echo "int main() { return 0; }" >> /tmp/legacy.c
    gcc -o /app/bin/legacy_auth_service /tmp/legacy.c

    # Download and perturb PyJWT 1.7.1
    curl -sL https://github.com/jpadilla/pyjwt/archive/refs/tags/1.7.1.tar.gz | tar xz -C /app/vendor
    mv /app/vendor/pyjwt-1.7.1 /app/vendor/PyJWT-1.7.1

    # Perturb RSA verification
    sed -i 's/verifier.verify(signature)/return False/g' /app/vendor/PyJWT-1.7.1/jwt/algorithms.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
