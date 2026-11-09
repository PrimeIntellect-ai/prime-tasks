#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip postgresql postgresql-contrib redis-server redis-tools sudo
    pip3 install pytest psycopg2-binary redis

    mkdir -p /app
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
service redis-server start
# Wait for postgres to be ready
sleep 2
su - postgres -c "psql -c 'CREATE DATABASE sensor_db;' || true"
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_data.py
import random
import csv

sensors = [f"s{i}" for i in range(1, 101)]
with open("/home/user/data/sensors.csv", "w", newline="") as f:
    writer = csv.writer(f)
    for i in range(500000):
        writer.writerow([1600000000 + i, random.choice(sensors), round(random.uniform(10.0, 100.0), 2)])
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
