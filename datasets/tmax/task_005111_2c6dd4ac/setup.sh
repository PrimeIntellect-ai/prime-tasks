#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
    pip3 install pytest flask gunicorn python-dotenv

    mkdir -p /home/user/app
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/clean

    cat << 'EOF' > /home/user/corpora/evil/evil_1.cypher
MATCH p=()-[*]->() RETURN p
EOF

    cat << 'EOF' > /home/user/corpora/evil/evil_2.cypher
CALL db.labels()
EOF

    cat << 'EOF' > /home/user/corpora/evil/evil_3.cypher
MATCH (a:Person), (b:Movie) RETURN a, b
EOF

    cat << 'EOF' > /home/user/corpora/clean/clean_1.cypher
MATCH (n:User {id: 123})-[:BOUGHT]->(p:Product) RETURN p
EOF

    cat << 'EOF' > /home/user/corpora/clean/clean_2.cypher
MATCH (a)-[r:KNOWS]->(b) WHERE a.age > 18 RETURN b
EOF

    cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /query {
            proxy_pass http://127.0.0.1:7687;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/.env
GRAPH_DB_URL=tcp://127.0.0.1:8080
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
nginx -c /home/user/app/nginx.conf &
# Mock flask app and mock DB would be started here
EOF
    chmod +x /home/user/app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
