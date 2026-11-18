#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        make \
        cmake \
        libjsoncpp-dev \
        libhiredis-dev \
        libpq-dev \
        nginx \
        redis-server \
        postgresql \
        curl

    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil /app/nginx

    # Baseline nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        server_name localhost;

        # Agent needs to add location /register here
    }
}
EOF

    # Start services script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
service redis-server start
nginx -c /app/nginx/nginx.conf
EOF
    chmod +x /app/start_services.sh

    # Clean corpus
    for i in {1..5}; do
        cat << EOF > /app/corpora/clean/clean_$i.json
{
  "nodes": [
    {"id": "b1", "type": "backup", "backup_type": "full", "timestamp": 1, "bytes": 1000},
    {"id": "z1", "type": "zone", "status": "ok"}
  ],
  "edges": [
    {"source": "b1", "target": "z1", "type": "stored_in"}
  ]
}
EOF
    done

    # Evil corpus
    # Evil 1: 4 hops
    cat << 'EOF' > /app/corpora/evil/evil_1.json
{
  "nodes": [
    {"id": "b1", "type": "backup", "backup_type": "full", "timestamp": 1, "bytes": 1000},
    {"id": "b2", "type": "backup", "backup_type": "incremental", "timestamp": 2, "bytes": 1000},
    {"id": "b3", "type": "backup", "backup_type": "incremental", "timestamp": 3, "bytes": 1000},
    {"id": "b4", "type": "backup", "backup_type": "incremental", "timestamp": 4, "bytes": 1000},
    {"id": "b5", "type": "backup", "backup_type": "incremental", "timestamp": 5, "bytes": 1000}
  ],
  "edges": [
    {"source": "b5", "target": "b4", "type": "derived_from"},
    {"source": "b4", "target": "b3", "type": "derived_from"},
    {"source": "b3", "target": "b2", "type": "derived_from"},
    {"source": "b2", "target": "b1", "type": "derived_from"}
  ]
}
EOF

    # Evil 2: compromised zone
    cat << 'EOF' > /app/corpora/evil/evil_2.json
{
  "nodes": [
    {"id": "b1", "type": "backup", "backup_type": "full", "timestamp": 1, "bytes": 1000},
    {"id": "z1", "type": "zone", "status": "compromised"}
  ],
  "edges": [
    {"source": "b1", "target": "z1", "type": "stored_in"}
  ]
}
EOF

    # Evil 3: sum > 500GB
    cat << 'EOF' > /app/corpora/evil/evil_3.json
{
  "nodes": [
    {"id": "b1", "type": "backup", "backup_type": "full", "timestamp": 1, "bytes": 200000000000},
    {"id": "b2", "type": "backup", "backup_type": "full", "timestamp": 2, "bytes": 200000000000},
    {"id": "b3", "type": "backup", "backup_type": "full", "timestamp": 3, "bytes": 200000000000}
  ],
  "edges": []
}
EOF

    # Evil 4: cycle
    cat << 'EOF' > /app/corpora/evil/evil_4.json
{
  "nodes": [
    {"id": "b1", "type": "backup", "backup_type": "incremental", "timestamp": 1, "bytes": 1000},
    {"id": "b2", "type": "backup", "backup_type": "incremental", "timestamp": 2, "bytes": 1000}
  ],
  "edges": [
    {"source": "b1", "target": "b2", "type": "derived_from"},
    {"source": "b2", "target": "b1", "type": "derived_from"}
  ]
}
EOF

    # Evil 5: no full backup reachable
    cat << 'EOF' > /app/corpora/evil/evil_5.json
{
  "nodes": [
    {"id": "b1", "type": "backup", "backup_type": "incremental", "timestamp": 1, "bytes": 1000}
  ],
  "edges": []
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
