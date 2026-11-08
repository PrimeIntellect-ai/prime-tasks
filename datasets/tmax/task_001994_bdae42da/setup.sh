#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl libssl-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app /home/user/secrets /home/user/.ssh /home/user/certs

    # 1. Create vulnerable C++ file
    cat << 'EOF' > /home/user/app/auth_service.cpp
#include <iostream>
#include <string>
#include <openssl/evp.h>

std::string getUserByToken(const std::string& token) {
    // Vulnerable to SQLi
    std::string query = "SELECT * FROM users WHERE token = '" + token + "'";
    return query;
}

void encryptData(const unsigned char* plaintext, int plaintext_len, const unsigned char* key, unsigned char* ciphertext) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    // Vulnerable to ECB mode
    EVP_EncryptInit_ex(ctx, EVP_aes_256_ecb(), NULL, key, NULL);

    int len;
    EVP_EncryptUpdate(ctx, ciphertext, &len, plaintext, plaintext_len);
    int ciphertext_len = len;

    EVP_EncryptFinal_ex(ctx, ciphertext + len, &len);
    ciphertext_len += len;

    EVP_CIPHER_CTX_free(ctx);
}

int main() {
    return 0;
}
EOF

    # 2. Create the encrypted secret
    echo "DB_PASS=SuperSecretPassword123!" > /tmp/plain.txt
    openssl enc -aes-256-ecb -K 6f6c645f7365637265745f6b65795f31323334353637383930313233343536 -in /tmp/plain.txt -out /home/user/secrets/db_config.enc
    rm /tmp/plain.txt

    # 3. Create the certificate chain
    cd /home/user/certs
    # Root
    openssl req -x509 -sha256 -days 365 -nodes -newkey rsa:2048 -subj "/CN=Root CA" -keyout root.key -out root.crt
    # Intermediate
    openssl req -new -newkey rsa:2048 -nodes -keyout intermediate.key -subj "/CN=Intermediate CA" -out intermediate.csr
    echo "basicConstraints=CA:TRUE" > /tmp/extfile.cnf
    openssl x509 -req -in intermediate.csr -CA root.crt -CAkey root.key -CAcreateserial -out intermediate.crt -days 365 -sha256 -extfile /tmp/extfile.cnf
    # Server
    openssl req -new -newkey rsa:2048 -nodes -keyout server.key -subj "/CN=server.local" -out server.csr
    openssl x509 -req -in server.csr -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -out server.crt -days 365 -sha256
    cd /

    chmod -R 777 /home/user
    chmod 700 /home/user/.ssh
