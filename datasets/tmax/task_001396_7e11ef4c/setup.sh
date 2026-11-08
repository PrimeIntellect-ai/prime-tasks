#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask redis

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/config
    mkdir -p /home/user/data_source
    mkdir -p /home/user/app/data
    mkdir -p /home/user/corpora/tz_evil
    mkdir -p /home/user/corpora/tz_clean

    # Populate tz_clean
    echo "Europe/London" > /home/user/corpora/tz_clean/1.txt
    echo "America/Argentina/Buenos_Aires" > /home/user/corpora/tz_clean/2.txt

    # Populate tz_evil
    echo "../../../etc/passwd" > /home/user/corpora/tz_evil/1.txt
    echo "America/New_York; rm -rf /" > /home/user/corpora/tz_evil/2.txt

    # Create start_services.sh
    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
# Startup script for NGINX, Flask, and Redis
EOF
    chmod +x /home/user/app/start_services.sh

    # Create config files
    cat << 'EOF' > /home/user/app/config/nginx.conf
# NGINX configuration
EOF

    cat << 'EOF' > /home/user/app/config/backend.env
# Backend environment variables
EOF

    chmod -R 777 /home/user
