#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_target

    # 1. Vulnerable perms
    touch /home/user/audit_target/config.ini
    touch /home/user/audit_target/tmp_cache.txt

    # 2. Insecure script
    cat << 'EOF' > /home/user/audit_target/encrypt.sh
#!/bin/bash
# Super secure encryption using shift of 7
cat $1 | tr '[A-Za-z]' '[H-ZA-Gh-za-g]'
EOF

    # 3. Ciphertext
    echo "CONFIDENTIAL: The backup server password is 'hunter2'." | tr '[A-Za-z]' '[H-ZA-Gh-za-g]' > /home/user/audit_target/secret_data.enc

    # 4. Server log
    cat << 'EOF' > /home/user/audit_target/server.log
[INFO] User admin logged in successfully.
[DEBUG] Checking API_KEY=aB3dE6gH9jK2mN5p for permissions.
[ERROR] Failed to process payment for card 1234567890123456 due to timeout.
[INFO] Another API_KEY=XYZ123ABC9876543 was used.
[DEBUG] User profile updated.
EOF

    chmod -R 777 /home/user

    # Fix specific permissions required by the task after the recursive chmod
    chmod 644 /home/user/audit_target/config.ini
    chmod 755 /home/user/audit_target/encrypt.sh
