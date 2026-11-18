#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/investigation
    cd /home/user/investigation

    # Generate RSA key and encrypt with passphrase 'purplemonkey123'
    openssl genpkey -algorithm RSA -out plain_key.pem -pkeyopt rsa_keygen_bits:2048
    openssl rsa -in plain_key.pem -out encrypted_key.pem -aes256 -passout pass:purplemonkey123

    # Create secret message and encrypt it
    echo "The payload was deployed via the vulnerable logging endpoint." > secret.txt.orig
    openssl rsa -in plain_key.pem -pubout -out pub_key.pem
    openssl pkeyutl -encrypt -in secret.txt.orig -pubin -inkey pub_key.pem -out secret.enc
    rm plain_key.pem pub_key.pem secret.txt.orig

    # Generate dictionary
    echo "password" > dict.txt
    echo "123456" >> dict.txt
    echo "admin" >> dict.txt
    echo "purplemonkey123" >> dict.txt
    echo "hunter2" >> dict.txt
    echo "qwerty" >> dict.txt

    # Generate incident logs with CC numbers
    cat << 'EOF' > incident_logs.txt
[2023-10-01 10:12:45] INFO: User login successful.
[2023-10-01 10:13:01] ERROR: Failed payment transaction for CC 4111-2222-3333-4444. Error code 500.
[2023-10-01 10:15:22] DEBUG: Raw payload: {"card": "5555666677778888", "cvv": "123"}
[2023-10-01 10:18:00] INFO: Processed 1234 items. No issues found.
[2023-10-01 10:20:11] WARN: Retry for account 9999-8888-7777-6666 triggered.
EOF

    chown -R user:user /home/user/investigation
    chmod -R 777 /home/user
