#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx
    pip3 install pytest flask redis scikit-learn requests pandas

    mkdir -p /home/user/app
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
daemon off;
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        # TODO: Route /api/ to Flask running on port 5000
    }
}
EOF

    cat << 'EOF' > /home/user/app/api.py
from flask import Flask, request, jsonify
import redis
import os

app = Flask(__name__)

# TODO: connect to Redis using REDIS_HOST and REDIS_PORT

@app.route('/api/ingest', methods=['POST'])
def ingest():
    data = request.json
    # TODO: Implement embedding computation and store in Redis
    return jsonify({"status": "success"})

@app.route('/api/search', methods=['GET'])
def search():
    query = request.args.get('query')
    # TODO: Implement search logic
    return jsonify({"results": []})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/data/training_data.csv
id,description
1,High performance gaming laptop with RTX 3080
2,Wireless noise cancelling headphones over ear
3,Mechanical keyboard with cherry mx red switches
4,27 inch 4K IPS monitor for color accurate work
5,Ergonomic wireless mouse with programmable buttons
6,USB-C docking station with dual HDMI output
7,1TB NVMe SSD PCIe Gen 4
8,Smart home speaker with voice assistant
9,Fitness tracker watch with heart rate monitor
10,Portable power bank 20000mAh fast charging
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
