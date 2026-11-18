#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl git postgresql postgresql-contrib redis-server sudo
    pip3 install pytest

    # Install Go 1.21
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    mkdir -p /app/backup-service
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
service redis-server start

# Wait for postgres
until sudo -u postgres psql -c '\q'; do
  sleep 1
done

sudo -u postgres psql -c "CREATE DATABASE backup_db;" || true
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';" || true

sudo -u postgres psql -d backup_db -c "
CREATE TABLE IF NOT EXISTS products (id SERIAL PRIMARY KEY, name TEXT);
CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name TEXT);
CREATE TABLE IF NOT EXISTS profiles (id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id));
CREATE TABLE IF NOT EXISTS orders (id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id));
CREATE TABLE IF NOT EXISTS order_items (id SERIAL PRIMARY KEY, order_id INT REFERENCES orders(id), product_id INT REFERENCES products(id));
CREATE TABLE IF NOT EXISTS system_logs (id SERIAL PRIMARY KEY, event TEXT);
CREATE TABLE IF NOT EXISTS departments (id SERIAL PRIMARY KEY, name TEXT);
CREATE TABLE IF NOT EXISTS employees (id SERIAL PRIMARY KEY, dept_id INT REFERENCES departments(id));
"
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/backup-service/config.env
DB_HOST=127.0.0.1
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=backup_db
EOF

    cd /app/backup-service
    go mod init backup-service
    go get github.com/lib/pq

    cat << 'EOF' > /app/corpus/clean/req1.json
{"tables": ["users", "orders"]}
EOF
    cat << 'EOF' > /app/corpus/clean/req2.json
{"tables": ["orders", "order_items", "products"]}
EOF
    cat << 'EOF' > /app/corpus/clean/req3.json
{"tables": ["users", "orders", "order_items", "products"]}
EOF
    cat << 'EOF' > /app/corpus/clean/req4.json
{"tables": ["departments", "employees"]}
EOF

    cat << 'EOF' > /app/corpus/evil/req1.json
{"tables": ["users", "products"]}
EOF
    cat << 'EOF' > /app/corpus/evil/req2.json
{"tables": ["users", "system_logs"]}
EOF
    cat << 'EOF' > /app/corpus/evil/req3.json
{"tables": ["users", "orders", "departments"]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
