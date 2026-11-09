#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go redis-server nginx zip unzip
    pip3 install pytest

    mkdir -p /app/raw/sensor_alpha /app/raw/sensor_beta
    echo "Alpha-v1.2 active" > /app/raw/sensor_alpha/meta.txt
    echo "Beta-v2.0 inactive" > /app/raw/sensor_beta/meta.txt
    # sensor_alpha: 2.5MB -> 3 chunks
    dd if=/dev/urandom of=/app/raw/sensor_alpha/data.bin bs=1M count=2 status=none
    dd if=/dev/urandom of=/app/raw/sensor_alpha/data.bin bs=512K count=1 oflag=append conv=notrunc status=none
    # sensor_beta: 1.2MB -> 2 chunks
    dd if=/dev/urandom of=/app/raw/sensor_beta/data.bin bs=1M count=1 status=none
    dd if=/dev/urandom of=/app/raw/sensor_beta/data.bin bs=200K count=1 oflag=append conv=notrunc status=none

    cd /app/raw
    zip -r ../sensor_alpha.zip sensor_alpha
    zip -r ../sensor_beta.zip sensor_beta
    cd /app
    tar -czvf dataset.tar.gz sensor_alpha.zip sensor_beta.zip
    rm -rf /app/raw sensor_alpha.zip sensor_beta.zip

    # Create barebones nginx conf for agent to edit
    cat << 'EOF' > /app/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    server {
        listen 8090;
        # TODO: Add reverse proxy for /api/ to http://127.0.0.1:8080
    }
}
EOF

    # Create start script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx.conf &
EOF
    chmod +x /app/start_services.sh
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
