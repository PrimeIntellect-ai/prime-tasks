#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libssl-dev openssl coreutils
    pip3 install pytest

    mkdir -p /home/user/bundles/dev/assets
    mkdir -p /home/user/bundles/staging/assets
    mkdir -p /home/user/bundles/prod/assets
    mkdir -p /home/user/bundles/dr/assets
    mkdir -p /home/user/src

    # Generate Root CAs
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout /tmp/ca1.key -out /tmp/ca1.pem -subj "/CN=Root CA 1"
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout /tmp/ca2.key -out /tmp/ca2.pem -subj "/CN=Root CA 2"

    # Generate Leaf certs
    openssl req -newkey rsa:2048 -nodes -keyout /tmp/leaf1.key -out /tmp/leaf1.csr -subj "/CN=App 1"
    openssl x509 -req -in /tmp/leaf1.csr -CA /tmp/ca1.pem -CAkey /tmp/ca1.key -CAcreateserial -out /tmp/leaf1.pem -days 365

    openssl req -newkey rsa:2048 -nodes -keyout /tmp/leaf2.key -out /tmp/leaf2.csr -subj "/CN=App 2"
    openssl x509 -req -in /tmp/leaf2.csr -CA /tmp/ca2.pem -CAkey /tmp/ca2.key -CAcreateserial -out /tmp/leaf2.pem -days 365

    # Helper to populate bundle
    populate_bundle() {
        local dir=$1
        local ca_pem=$2
        local cert_pem=$3
        local csp=$4
        local corrupt_hash=$5

        cp $ca_pem $dir/ca.pem
        cp $cert_pem $dir/cert.pem
        echo "$csp" > $dir/csp.txt

        echo "console.log('test');" > $dir/assets/app.js
        echo "<h1>Hello</h1>" > $dir/assets/index.html

        cd $dir
        sha256sum assets/app.js assets/index.html > manifest.sha256

        if [ "$corrupt_hash" = "true" ]; then
            echo "console.log('malicious injected code');" >> assets/app.js
        fi
        cd - >/dev/null
    }

    # 1. DEV: Valid Cert, Valid Hash, Invalid CSP
    populate_bundle "/home/user/bundles/dev" "/tmp/ca1.pem" "/tmp/leaf1.pem" "Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline';" "false"

    # 2. STAGING: Invalid Cert (Mismatched CA), Valid Hash, Valid CSP
    populate_bundle "/home/user/bundles/staging" "/tmp/ca1.pem" "/tmp/leaf2.pem" "Content-Security-Policy: default-src 'self'; script-src 'self';" "false"

    # 3. PROD: Valid Cert, Invalid Hash, Valid CSP
    populate_bundle "/home/user/bundles/prod" "/tmp/ca1.pem" "/tmp/leaf1.pem" "Content-Security-Policy: default-src 'self'; script-src 'self';" "true"

    # 4. DR: Valid everything
    populate_bundle "/home/user/bundles/dr" "/tmp/ca1.pem" "/tmp/leaf1.pem" "Content-Security-Policy: default-src 'self'; script-src 'self' https://trusted.cdn.com;" "false"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/bundles /home/user/src
    chmod -R 777 /home/user
