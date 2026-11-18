#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest PyJWT

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_repo

    cat << 'EOF' > /home/user/app_repo/app.py
import jwt

# TODO: Move this to environment variables before production!
JWT_SECRET_KEY = "Sup3rS3cr3t_DevSecOps_K3y_2024!"

def authenticate_user(token):
    try:
        payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=["HS256"])
        return payload
    except Exception as e:
        return None
EOF

    cat << 'EOF' > /home/user/app_repo/config.json
{
  "service_name": "data-aggregator",
  "version": "1.0.2",
  "run_as": "root",
  "bind_port": 8080,
  "debug_mode": true
}
EOF

    chmod -R 777 /home/user
