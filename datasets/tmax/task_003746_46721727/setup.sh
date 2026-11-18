#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip postgresql redis-server sudo curl jq
    pip3 install pytest psycopg2-binary flask redis

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /app/api

    # Create corpus files
    cat << 'EOF' > /app/corpus/clean/clean1.json
[
  {"timestamp": "2023-10-01T10:00:00Z", "user_id": "u123", "source": "A", "target": "B"},
  {"timestamp": "2023-10-01T10:05:00Z", "user_id": "u123", "source": "B", "target": "A"}
]
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.json
[
  {"timestamp": "2023-10-01T10:00:00Z", "user_id": "u456", "source": "A", "target": "A"},
  {"timestamp": "2023-10-01T10:01:00Z", "user_id": "u456", "source": "A", "target": "B"},
  {"timestamp": "2023-10-01T10:02:00Z", "user_id": "u456", "source": "B", "target": "A"}
]
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.json
[
  {"timestamp": "2023-10-01T10:00:00Z", "user_id": "u123", "source": "A", "target": "C"}
]
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.json
[
  {"timestamp": "2023-10-01T10:00:00Z", "user_id": "u999", "source": "A", "target": "B"},
  {"timestamp": "2023-10-01T10:01:00Z", "user_id": "u999", "source": "A", "target": "B"},
  {"timestamp": "2023-10-01T10:02:00Z", "user_id": "u999", "source": "A", "target": "B"},
  {"timestamp": "2023-10-01T10:03:00Z", "user_id": "u999", "source": "A", "target": "B"}
]
EOF

    # Setup Postgres DB initialization
    cat << 'EOF' > /app/init_db.sql
CREATE DATABASE audit;
\c audit;
CREATE TABLE network_graph (
    source_node VARCHAR(255),
    dest_node VARCHAR(255),
    cost INT
);
INSERT INTO network_graph (source_node, dest_node, cost) VALUES ('A', 'B', 5);
INSERT INTO network_graph (source_node, dest_node, cost) VALUES ('B', 'A', 5);
INSERT INTO network_graph (source_node, dest_node, cost) VALUES ('B', 'C', 15);
INSERT INTO network_graph (source_node, dest_node, cost) VALUES ('A', 'A', 0);
ALTER USER postgres WITH PASSWORD 'password';
EOF

    # Setup Flask API
    cat << 'EOF' > /app/api/app.py
from flask import Flask
app = Flask(__name__)
@app.route('/')
def hello():
    return "Audit API Running"
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    # Setup start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service redis-server start
service postgresql start

# Wait for postgres
until sudo -u postgres psql -c '\q'; do
  sleep 1
done

# Initialize DB if not already done
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw audit; then
    sudo -u postgres psql -f /app/init_db.sql
fi

# Start Flask API
nohup python3 /app/api/app.py > /app/api/api.log 2>&1 &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
