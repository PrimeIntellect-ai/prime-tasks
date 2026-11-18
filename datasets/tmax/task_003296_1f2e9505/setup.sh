#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang postgresql redis-server sudo
    pip3 install pytest redis psycopg2-binary

    mkdir -p /app

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
redis-server --daemonize yes

# Wait for postgres to be ready
until su - postgres -c "psql -c '\q'" >/dev/null 2>&1; do sleep 1; done

# Setup database
su - postgres -c "psql -c \"CREATE USER auditor WITH PASSWORD 'audit123';\""
su - postgres -c "psql -c \"CREATE DATABASE compliance;\""
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE compliance TO auditor;\""
su - postgres -c "psql -d compliance -c \"CREATE TABLE access_edges (source_id VARCHAR, target_id VARCHAR);\""
su - postgres -c "psql -d compliance -c \"GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO auditor;\""

# Insert some mock data
su - postgres -c "psql -d compliance -c \"INSERT INTO access_edges VALUES ('A', 'B'), ('B', 'C'), ('A', 'C'), ('C', 'D');\""
redis-cli set override:A:E ALLOW
redis-cli set override:B:E DENY
EOF
    chmod +x /app/start_services.sh

    # Create oracle python script
    cat << 'EOF' > /app/oracle.py
import sys
import json
import redis
import psycopg2
from collections import deque

def main():
    if len(sys.argv) != 3:
        return
    src = sys.argv[1]
    dst = sys.argv[2]

    r = redis.Redis(host='localhost', port=6379, decode_responses=True)
    val = r.get(f"override:{src}:{dst}")
    if val == "ALLOW":
        print(json.dumps({"status":"ALLOW","path":[src,dst],"reason":"redis_override"}))
        return
    elif val == "DENY":
        print(json.dumps({"status":"DENY","path":[],"reason":"redis_override"}))
        return

    conn = psycopg2.connect(dbname="compliance", user="auditor", password="audit123", host="localhost")
    cur = conn.cursor()
    cur.execute("SELECT source_id, target_id FROM access_edges")
    edges = cur.fetchall()

    adj = {}
    for u, v in edges:
        adj.setdefault(u, []).append(v)

    for k in adj:
        adj[k].sort()

    q = deque([[src]])
    visited = set([src])

    found_path = None
    while q:
        path = q.popleft()
        node = path[-1]
        if node == dst:
            found_path = path
            break
        for nxt in adj.get(node, []):
            if nxt not in visited:
                visited.add(nxt)
                q.append(path + [nxt])

    if found_path:
        print(json.dumps({"status":"ALLOW","path":found_path,"reason":"graph_path"}))
    else:
        print(json.dumps({"status":"DENY","path":[],"reason":"no_path"}))

if __name__ == "__main__":
    main()
EOF

    # Create oracle binary wrapper
    cat << 'EOF' > /app/oracle_audit_bin
#!/bin/bash
python3 /app/oracle.py "$1" "$2"
EOF
    chmod +x /app/oracle_audit_bin

    # Create fuzz pairs
    cat << 'EOF' > /app/fuzz_pairs.txt
A B
A C
A D
A E
B E
C D
X Y
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
