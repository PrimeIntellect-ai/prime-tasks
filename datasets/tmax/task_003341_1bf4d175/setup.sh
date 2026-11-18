#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx g++ supervisor curl psmisc
    pip3 install pytest

    # Create directories
    mkdir -p /app/wal_data
    mkdir -p /var/log/supervisor

    # Initialize WAL files so initial tests pass immediately
    touch /app/wal_data/wal_1.dat
    ln -s /app/wal_data/wal_1.dat /app/wal_data/active.wal

    # Create WAL writer script
    cat << 'EOF' > /app/wal_writer.py
import os, time, struct

os.makedirs('/app/wal_data', exist_ok=True)
record_id = 1
file_idx = 1

def write_record(f, rec_id, data):
    f.write(b'WALR')
    f.write(struct.pack('<I', rec_id))
    f.write(struct.pack('<I', len(data)))
    f.write(data.encode('ascii'))

while True:
    filename = f'/app/wal_data/wal_{file_idx}.dat'
    with open(filename, 'wb') as f:
        for _ in range(20):
            write_record(f, record_id, f'Payload for record {record_id}')
            record_id += 1
            time.sleep(0.5)

    tmp_link = '/app/wal_data/active.wal.tmp'
    if os.path.lexists(tmp_link):
        os.remove(tmp_link)
    os.symlink(filename, tmp_link)
    os.rename(tmp_link, '/app/wal_data/active.wal')
    file_idx += 1
EOF

    # Configure supervisor
    cat << 'EOF' > /etc/supervisor/conf.d/supervisord.conf
[supervisord]
nodaemon=true
user=root

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true

[program:wal_writer]
command=/usr/bin/python3 /app/wal_writer.py
autostart=true
autorestart=true
EOF

    # Ensure nginx listens on 8000 by default (as per task description)
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8000 default_server;
    listen [::]:8000 default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

    # Start supervisor in the background for the initial state test if needed
    # Note: Apptainer %post processes don't persist, but we can try to start it 
    # if the test runs in the same context, though typically the test framework handles it.
    # We will rely on the test framework starting supervisord or the services.

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
