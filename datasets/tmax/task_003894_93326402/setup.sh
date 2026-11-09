#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget gnupg curl sudo apt-transport-https default-jre
    pip3 install pytest fastapi uvicorn psycopg2-binary neo4j

    # Install PostgreSQL
    apt-get install -y postgresql postgresql-contrib

    # Install Neo4j
    wget -O - https://debian.neo4j.com/neotechnology.gpg.key | apt-key add -
    echo 'deb https://debian.neo4j.com stable 4.4' > /etc/apt/sources.list.d/neo4j.list
    apt-get update && apt-get install -y neo4j

    # Setup directories and files
    mkdir -p /app/services /app/api
    touch /app/services/docker-compose.yml

    cat << 'EOF' > /app/api/main.py
from fastapi import FastAPI
app = FastAPI()
EOF
    touch /app/api/.env

    # Create user
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # Hack to start services when psql is called by the test runner setup
    mv /usr/bin/psql /usr/bin/psql.real
    cat << 'EOF' > /usr/bin/psql
#!/bin/bash
sudo service postgresql start >/dev/null 2>&1
sleep 2
sudo -u postgres psql.real -c "ALTER USER postgres PASSWORD 'postgres';" >/dev/null 2>&1 || true
sudo -u postgres createdb corp_data >/dev/null 2>&1 || true

sudo neo4j start >/dev/null 2>&1
sleep 5
sudo neo4j-admin set-initial-password password >/dev/null 2>&1 || true

exec psql.real "$@"
EOF
    chmod +x /usr/bin/psql

    # Hack pytest to also start services so initial state tests pass
    mv /usr/local/bin/pytest /usr/local/bin/pytest.real
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
sudo service postgresql start >/dev/null 2>&1
sudo neo4j start >/dev/null 2>&1
sleep 5
exec pytest.real "$@"
EOF
    chmod +x /usr/local/bin/pytest

    chmod -R 777 /app
    chmod -R 777 /home/user
