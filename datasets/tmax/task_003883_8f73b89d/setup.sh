#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl libssl-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the hash file
    echo -n "e074d20ebae1e9ef5e0e64b4c7fcba44ea92b3a0cc1f4ba401e4a3aa82285a22" > /home/user/pass_hash.txt

    # Generate the old encrypted key using openssl to bypass ssh-keygen's 5-character minimum passphrase limit
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /home/user/old_key.pem -aes-128-cbc -pass pass:wolf

    # Create the audit log containing the leaks
    echo "Audit started at 10:00 AM." > /home/user/audit.log
    echo "User attempted to login with password: wolf" >> /home/user/audit.log
    echo "SSH key generation output:" >> /home/user/audit.log
    cat /home/user/old_key.pem >> /home/user/audit.log
    echo "Audit finished at 10:05 AM. Next steps: ensure wolf is rotated." >> /home/user/audit.log

    chmod -R 777 /home/user
