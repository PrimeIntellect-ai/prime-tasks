#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import csv

os.makedirs('/home/user/raw_data', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)

data_server_1 = [
    ['e001', '2023-10-01T10:00:00Z', 'srv_alpha', 'nginx', 'user www-data;\nworker_processes auto;'],
    ['e003', '2023-10-01T10:05:00Z', 'srv_alpha', 'mysql', 'innodb_buffer_pool_size=1G\nmax_connections=500\nquery_cache_size=0'],
    ['e006', '2023-10-01T10:15:00Z', 'srv_alpha', 'nginx', 'user www-data;\nworker_processes 4;\npid /run/nginx.pid;']
]

data_server_2 = [
    ['e002', '2023-10-01T10:02:00Z', 'srv_beta', 'nginx', 'worker_processes auto;'],
    ['e004', '2023-10-01T10:08:00Z', 'srv_beta', 'redis', 'maxmemory 2gb\nmaxmemory-policy allkeys-lru\nappendonly yes\nappendfsync everysec'],
    ['e005', '2023-10-01T10:12:00Z', 'srv_beta', 'nginx', 'worker_processes 2;\nworker_connections 1024;'],
    ['e007', '2023-10-01T10:20:00Z', 'srv_beta', 'nginx', 'worker_processes 4;\nworker_connections 2048;\nkeepalive_timeout 65;']
]

def write_csv(filename, data):
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['event_id', 'timestamp', 'server_id', 'service_name', 'config_diff'])
        writer.writerows(data)

write_csv('/home/user/raw_data/server_alpha.csv', data_server_1)
write_csv('/home/user/raw_data/server_beta.csv', data_server_2)
"

    chmod -R 777 /home/user
