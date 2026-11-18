#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        libpq-dev \
        libhiredis-dev \
        libjson-c-dev \
        postgresql \
        redis-server \
        sudo

    pip3 install pytest requests redis psycopg2-binary

    mkdir -p /app
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
# Mocking the service start for the container environment
service postgresql start
service redis-server start

# Wait for postgres
sleep 2

sudo -u postgres psql -c "CREATE USER admin WITH PASSWORD 'password';"
sudo -u postgres psql -c "CREATE DATABASE graphdb OWNER admin;"

sudo -u postgres psql -d graphdb -c "
CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(50), category VARCHAR(50));
CREATE TABLE follows (follower_id INT, followee_id INT, engagement_score INT);

INSERT INTO users VALUES (1, 'Alice', 'tech'), (2, 'Bob', 'tech'), (3, 'Charlie', 'art');
INSERT INTO follows VALUES (2, 1, 95), (3, 1, 80), (4, 1, 99), (5, 1, 20);
INSERT INTO follows VALUES (1, 2, 50), (3, 2, 60);
"
EOF
    chmod +x /app/start_services.sh
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
