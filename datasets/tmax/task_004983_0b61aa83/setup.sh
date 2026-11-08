#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip postgresql redis-server nginx g++ make libpq-dev libhiredis-dev nlohmann-json3-dev curl sudo
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil /home/user/query_router

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
service redis-server start
su - postgres -c "psql -c \"CREATE USER appuser WITH PASSWORD 'secret';\""
su - postgres -c "psql -c \"CREATE DATABASE appdb OWNER appuser;\""
su - postgres -c "psql -d appdb -c \"CREATE TABLE items (id SERIAL PRIMARY KEY, data TEXT); INSERT INTO items (data) VALUES ('A'), ('B'), ('C'), ('D');\""
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /home/user/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/query {
            # proxy_pass directive missing
        }
    }
}
EOF

    cat << 'EOF' > /home/user/query_router/config.hpp
#pragma once
#include <string>

const std::string PG_CONN = "dbname=wrong user=wrong password=wrong host=127.0.0.1 port=5432";
const std::string REDIS_HOST = "127.0.0.1";
const int REDIS_PORT = 6379;
EOF

    cat << 'EOF' > /home/user/query_router/db_handler.cpp
#include <string>

std::string execute_postgres_query(const std::string& base_query, int limit, int offset) {
    // Missing LIMIT and OFFSET
    return base_query;
}
EOF

    cat << 'EOF' > /home/user/query_router/sanitizer.cpp
#include <string>

bool is_safe_payload(const std::string& json_body) {
    // Missing logic
    return true;
}
EOF

    cat << 'EOF' > /home/user/query_router/Makefile
all:
	echo '#!/bin/bash' > query_router
	echo 'python3 -m http.server 8081' >> query_router
	chmod +x query_router
EOF

    echo '{"query": "SELECT * FROM items"}' > /app/corpora/clean/1.json
    echo '{"query": "SELECT * FROM items UNION SELECT 1,2"}' > /app/corpora/evil/1.json

    cat << 'EOF' > /app/verify_corpora.py
import requests
print("Verification script")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
