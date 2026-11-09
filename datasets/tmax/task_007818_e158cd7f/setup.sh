#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs
    cd /home/user

    # 1. Create the ELF binary and inject the hash
    echo 'int main(){return 0;}' | gcc -x c - -o intercept_daemon
    PASSWORD="supernova_admin"
    echo -n "$PASSWORD" | sha256sum | awk '{printf "%s", $1}' > /tmp/hash.bin
    objcopy --add-section .key_hash=/tmp/hash.bin intercept_daemon
    rm /tmp/hash.bin

    # 2. Create the wordlist
    cat << 'EOF' > passwords.txt
apple123
password
admin1234
supernova_admin
qwerty
letmein1
EOF

    # 3. Create the encrypted file
    echo "/home/user/certs" > traffic_keys.txt
    openssl enc -aes-256-cbc -pbkdf2 -pass pass:$PASSWORD -in traffic_keys.txt -out traffic_keys.enc
    rm traffic_keys.txt

    # 4. Create the certificates (Valid chain)
    cd /home/user/certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ca.key -out ca.crt -subj "/CN=Fake Root CA"
    openssl req -nodes -newkey rsa:2048 -keyout server.key -out server.csr -subj "/CN=malicious.local"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365
    cd /home/user

    # 5. Create the CSP header file
    cat << 'EOF' > csp_header.txt
HTTP/1.1 200 OK
Date: Wed, 21 Oct 2023 07:28:00 GMT
Content-Security-Policy: default-src 'self'; script-src 'self' https://scripts.trusted.com https://cdn.malicious.local; object-src 'none'
Content-Type: text/html
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
