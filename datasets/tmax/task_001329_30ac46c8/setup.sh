#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_configs
    cat << 'EOF' > /home/user/app_configs/db.conf
DB_USER=admin
DB_PASSWORD=OldVulnerablePass123
DB_HOST=localhost
EOF

    cat << 'EOF' > /home/user/app_configs/aws.conf
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_REGION=us-east-1
EOF

    cat << 'EOF' > /home/user/app_configs/app.conf
APP_ENV=production
DB_PASSWORD=OldVulnerablePass123
AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF
EOF

    chmod 644 /home/user/app_configs/*.conf

    chmod -R 777 /home/user
    chmod 644 /home/user/app_configs/*.conf
    chmod 777 /home/user/app_configs
