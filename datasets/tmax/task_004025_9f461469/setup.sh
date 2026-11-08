#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        redis-server \
        curl

    pip3 install pytest fastapi uvicorn redis

    mkdir -p /home/user/app/api
    mkdir -p /home/user/tests/corpora/evil
    mkdir -p /home/user/tests/corpora/clean

    # Create /home/user/app/api/parser.py
    cat << 'EOF' > /home/user/app/api/parser.py
def parse_expression(expr):
    # Dummy vulnerable parser logic
    pass
EOF

    # Create /home/user/app/nginx.conf
    cat << 'EOF' > /home/user/app/nginx.conf
server {
    listen 8080;
    server_name localhost;

    location /graphql {
        # TODO: Fix proxy_pass
        proxy_pass http://127.0.0.1:9999;
    }
}
EOF

    # Create /home/user/app/start_services.sh
    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/app/nginx.conf
uvicorn api.main:app --host 127.0.0.1 --port 8000 &
EOF
    chmod +x /home/user/app/start_services.sh

    # Create corpora files
    cat << 'EOF' > /home/user/tests/corpora/clean/query1.graphql
query { user(id: 1) @filter(expr: "user.id == 5") { name } }
EOF

    cat << 'EOF' > /home/user/tests/corpora/evil/query1.graphql
query { user(id: 1) @filter(expr: "((((((user.id == 5))))))") { name } }
EOF

    cat << 'EOF' > /home/user/tests/corpora/evil/query2.graphql
query { user(id: 1) @filter(expr: "__internal_migrated_schema") { name } }
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
