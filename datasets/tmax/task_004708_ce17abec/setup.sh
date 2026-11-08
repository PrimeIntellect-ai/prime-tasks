#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip postgresql socat jq curl sudo
pip3 install pytest

# Configure PostgreSQL to trust local connections
sed -i 's/peer/trust/g' /etc/postgresql/*/main/pg_hba.conf
sed -i 's/md5/trust/g' /etc/postgresql/*/main/pg_hba.conf
sed -i 's/scram-sha-256/trust/g' /etc/postgresql/*/main/pg_hba.conf

mkdir -p /app

cat << 'EOF' > /app/seed.sql
CREATE DATABASE company;
\c company
CREATE TABLE employees (id SERIAL PRIMARY KEY, name VARCHAR(50), manager_id INT);
INSERT INTO employees (id, name, manager_id) VALUES 
(1, 'Alice', NULL),
(2, 'Bob', 1),
(3, 'Charlie', 2),
(4, 'Diana', 1),
(5, 'Eve', 4);
EOF

cat << 'EOF' > /app/query.sql
-- Broken query with cross join
SELECT e1.id, e1.name, 0 as depth
FROM employees e1, employees e2
WHERE e1.id = :v_manager_id;
EOF

cat << 'EOF' > /app/server.sh
#!/bin/bash
# Missing proper port binding and fork
socat TCP-LISTEN:8080 EXEC:/app/handle_req.sh
EOF

cat << 'EOF' > /app/handle_req.sh
#!/bin/bash
read request
MANAGER_ID=$(echo "$request" | grep -oP 'manager_id=\K\d+')
# Missing HTTP headers
psql -U postgres -d company -v v_manager_id="$MANAGER_ID" -f /app/query.sql -tA | jq -R -s -c 'split("\n")[:-1] | map(split("|") | {id: .[0]|tonumber, name: .[1], depth: .[2]|tonumber})'
EOF

cat << 'EOF' > /app/start.sh
#!/bin/bash
service postgresql start
su - postgres -c "psql -f /app/seed.sql" || true
/app/server.sh &
EOF

chmod +x /app/*.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
