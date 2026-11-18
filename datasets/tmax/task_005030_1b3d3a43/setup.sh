#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import zlib
import json

base_dir = '/home/user/sys_configs'
os.makedirs(os.path.join(base_dir, 'region_us/db'), exist_ok=True)
os.makedirs(os.path.join(base_dir, 'region_us/web'), exist_ok=True)
os.makedirs(os.path.join(base_dir, 'region_eu/db'), exist_ok=True)
os.makedirs(os.path.join(base_dir, 'region_eu/cache'), exist_ok=True)

configs = [
    {
        'path': 'region_us/web/nginx_v1.ccb',
        'timestamp': 1620000000,
        'json': {"service": "nginx", "version": "1.18.0", "parameters": {"worker_processes": "auto", "listen": "80", "server_name": "us.example.com", "root": "/var/www/html", "index": "index.html"}}
    },
    {
        'path': 'region_eu/cache/redis_master.ccb',
        'timestamp': 1620000100,
        'json': {"service": "redis", "version": "6.0", "parameters": {"port": "6379", "bind": "127.0.0.1", "protected-mode": "yes"}}
    },
    {
        'path': 'region_us/db/pg_main.ccb',
        'timestamp': 1620000200,
        'json': {"service": "postgres", "version": "13.2", "parameters": {"max_connections": "100", "shared_buffers": "128MB", "work_mem": "4MB", "maintenance_work_mem": "64MB", "effective_cache_size": "4GB", "log_timezone": "UTC", "datestyle": "iso, mdy", "timezone": "UTC"}}
    },
    {
        'path': 'region_us/web/nginx_v2.ccb',
        'timestamp': 1620000300,
        'json': {"service": "nginx", "version": "1.19.0", "parameters": {"worker_processes": "auto", "listen": "443", "ssl_certificate": "/etc/ssl/certs/us.example.com.crt", "ssl_certificate_key": "/etc/ssl/private/us.example.com.key", "server_name": "us.example.com", "root": "/var/www/html"}}
    },
    {
        'path': 'region_eu/db/pg_replica.ccb',
        'timestamp': 1620000200,
        'json': {"service": "postgres-replica", "version": "13.2", "parameters": {"max_connections": "200", "shared_buffers": "256MB"}}
    }
]

for cfg in configs:
    json_str = json.dumps(cfg['json']).encode('utf-8')
    compressed = zlib.compress(json_str)

    magic = b'CCB\x01'
    timestamp = cfg['timestamp']
    length = len(compressed)

    header = struct.pack('<4sII', magic, timestamp, length)

    full_path = os.path.join(base_dir, cfg['path'])
    with open(full_path, 'wb') as f:
        f.write(header + compressed)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
