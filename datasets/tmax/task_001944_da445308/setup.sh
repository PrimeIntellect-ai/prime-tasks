#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask redis hypothesis fastapi uvicorn requests

    mkdir -p /app

    cat << 'EOF' > /app/api.py
# Skeleton for API server
# Implement your Flask or FastAPI app here
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
# Start Redis
redis-server --daemonize yes

# Start Python API
# TODO: Start your Python server here in the background
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/tests

    chmod -R 777 /app
    chmod -R 777 /home/user
