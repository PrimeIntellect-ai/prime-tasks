#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        redis-server \
        g++ \
        make \
        cmake \
        pkg-config \
        libcurl4-openssl-dev \
        libhiredis-dev \
        nlohmann-json3-dev \
        zlib1g-dev \
        curl

    pip3 install pytest flask redis

    # Configure Nginx
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    server_name 127.0.0.1;
    root /var/www/html;
    location / {
        autoindex on;
    }
}
EOF

    # Create files
    mkdir -p /var/www/html/files
    for i in $(seq 1 200); do
        echo -e "Line $i:  Double  spaces  and  carriage  returns.\r" >> /var/www/html/files/file1.txt
    done

    for i in $(seq 1 100); do
        echo -e "Data $i:  Double  spaces  here.\r" >> /var/www/html/files/file2.dat
    done

    for i in $(seq 1 200); do
        echo -e "More $i:  Double  spaces  and  carriage  returns.\r" >> /var/www/html/files/file3.txt
    done

    # Setup app
    mkdir -p /app/coordinator

    cat << 'EOF' > /app/coordinator/config.json
{
  "redis_host": "/var/run/redis/redis.sock",
  "redis_port": 0,
  "storage_url": "http://localhost/files/"
}
EOF

    cat << 'EOF' > /app/coordinator/app.py
import json
import redis
from flask import Flask

app = Flask(__name__)

with open('/app/coordinator/config.json') as f:
    config = json.load(f)

r = redis.Redis(host=config['redis_host'], port=config['redis_port'])

@app.route('/api/stale_ids')
def stale_ids():
    r.ping()
    return "1,2,3"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service nginx start
redis-server --daemonize yes
sleep 1

redis-cli set file:1 '{"filepath": "file1.txt", "is_text": true}'
redis-cli set file:2 '{"filepath": "file2.dat", "is_text": false}'
redis-cli set file:3 '{"filepath": "file3.txt", "is_text": true}'

python3 /app/coordinator/app.py &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
