#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_env/bin
    mkdir -p /home/user/app_env/logs
    mkdir -p /home/user/app_env/config

    # 1. Integrity
    echo '#!/bin/bash' > /home/user/app_env/bin/start.sh
    echo 'echo "Starting"' >> /home/user/app_env/bin/start.sh

    echo '#!/bin/bash' > /home/user/app_env/bin/deploy.sh
    echo 'echo "Deploying"' >> /home/user/app_env/bin/deploy.sh

    # Calculate valid hashes
    cd /home/user/app_env/bin
    sha256sum start.sh deploy.sh > /home/user/app_env/known_hashes.txt

    # Modify deploy.sh to invalidate hash
    echo 'echo "Malicious payload"' >> /home/user/app_env/bin/deploy.sh
    cd /home/user

    # 2. Permissions (files created here, permissions set after chmod 777)
    touch /home/user/app_env/bin/suid_tool
    touch /home/user/app_env/config/settings.json

    # 3. Redaction
    echo "User login success" > /home/user/app_env/logs/access.log
    echo "Req: API_KEY=1234567890abcdef from 10.0.0.1" >> /home/user/app_env/logs/access.log
    echo "Req: API_KEY=ABCDEF1234567890 from 10.0.0.2" >> /home/user/app_env/logs/error.log
    echo "Some safe log API_KEY=short" >> /home/user/app_env/logs/access.log

    # 4. CSP
    echo "Header set X-Frame-Options DENY" > /home/user/app_env/config/app.conf

    chmod -R 777 /home/user

    # Restore specific permissions that would be overwritten by chmod -R 777
    chmod 4755 /home/user/app_env/bin/suid_tool
    chmod 666 /home/user/app_env/config/settings.json
