#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget unzip tar
    pip3 install pytest cryptography

    # Create directories
    mkdir -p /app/certs
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Download and extract PyJWT 2.6.0
    cd /app
    wget https://github.com/jpadilla/pyjwt/archive/refs/tags/2.6.0.tar.gz
    tar -xzf 2.6.0.tar.gz
    mv pyjwt-2.6.0 PyJWT-2.6.0
    rm 2.6.0.tar.gz

    # Perturb algorithms.py
    sed -i 's/public_key.verify(signature, msg, padding.PKCS1v15(), self.hash_alg())/return False # VENDORED_CORRUPTION/' /app/PyJWT-2.6.0/jwt/algorithms.py

    # Generate certificates and keys
    cd /app/certs

    # Root CA
    openssl genrsa -out ca.key 2048
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -out ca.crt -subj "/C=US/ST=State/L=City/O=Org/OU=Root/CN=RootCA"

    # Leaf Cert
    openssl genrsa -out leaf.key 2048
    openssl req -new -key leaf.key -out leaf.csr -subj "/C=US/ST=State/L=City/O=Org/OU=Leaf/CN=LeafCert"
    openssl x509 -req -in leaf.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out leaf.crt -days 500 -sha256

    # Random Key for invalid tokens
    openssl genrsa -out random.key 2048

    # Generate test corpus
    cat << 'EOF' > /app/generate_corpus.py
import os
import sys
sys.path.insert(0, '/app/PyJWT-2.6.0')
import jwt
from cryptography.hazmat.primitives import serialization

with open('/app/certs/leaf.key', 'rb') as f:
    leaf_key = serialization.load_pem_private_key(f.read(), password=None)

with open('/app/certs/random.key', 'rb') as f:
    random_key = serialization.load_pem_private_key(f.read(), password=None)

# Create Evil corpus (5 files)
for i in range(5):
    payload = {"sub": f"user{i}", "role": "admin"}
    token = jwt.encode(payload, leaf_key, algorithm="RS256")
    cmdline = f"my_service\0--token\0{token}\0"
    with open(f'/app/corpora/evil/file{i}.cmd', 'w') as f:
        f.write(cmdline)

# Create Clean corpus (5 files)
# 1. No token
with open('/app/corpora/clean/file0.cmd', 'w') as f:
    f.write("my_service\0--verbose\0")

# 2-4. Invalid signature (signed with random key)
for i in range(1, 4):
    payload = {"sub": f"user{i}", "role": "admin"}
    token = jwt.encode(payload, random_key, algorithm="RS256")
    cmdline = f"my_service\0--token\0{token}\0"
    with open(f'/app/corpora/clean/file{i}.cmd', 'w') as f:
        f.write(cmdline)

# 5. Malformed string
with open('/app/corpora/clean/file4.cmd', 'w') as f:
    f.write("my_service\0--token\0not.a.jwt\0")
EOF

    # Fix the perturbed library temporarily to generate the corpus, then re-perturb
    sed -i 's/return False # VENDORED_CORRUPTION/public_key.verify(signature, msg, padding.PKCS1v15(), self.hash_alg())/' /app/PyJWT-2.6.0/jwt/algorithms.py
    python3 /app/generate_corpus.py
    sed -i 's/public_key.verify(signature, msg, padding.PKCS1v15(), self.hash_alg())/return False # VENDORED_CORRUPTION/' /app/PyJWT-2.6.0/jwt/algorithms.py

    rm /app/generate_corpus.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
