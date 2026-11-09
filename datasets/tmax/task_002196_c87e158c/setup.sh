#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/app/uploads/
    mkdir -p /home/user/auth_tokens/

    # Create the dropped malicious file
    echo -n "MALICIOUS_TOKEN_12345" > /home/user/auth_tokens/admin_token.txt

    # Set dangerous permissions
    chmod 0777 /home/user/auth_tokens/admin_token.txt

    # Create the upload log
    cat << 'EOF' > /home/user/uploads_log.txt
2023-10-25T08:12:01 | 192.168.1.10 | /api/upload | profile.jpg | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
2023-10-25T08:15:22 | 192.168.1.15 | /api/upload | resume.pdf | 8a1b3c9d7e6f...
2023-10-25T08:17:45 | 10.0.0.99 | /api/upload | ../../auth_tokens/admin_token.txt | 38848d601b3433a7eaf2aebf23fc63351e23f0340b080ba6b7dc446e50ec5696
2023-10-25T08:20:00 | 192.168.1.20 | /api/upload | logo.png | c1dfd9...
EOF

    chmod -R 777 /home/user
