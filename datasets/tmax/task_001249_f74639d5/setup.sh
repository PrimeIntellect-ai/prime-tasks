#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/compliance.db <<'EOF'
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE roles (id INTEGER PRIMARY KEY, role_name TEXT);
CREATE TABLE systems (id INTEGER PRIMARY KEY, sys_name TEXT);
CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER);
CREATE TABLE role_systems (role_id INTEGER, system_id INTEGER);

INSERT INTO users (id, name) VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');
INSERT INTO roles (id, role_name) VALUES (1, 'Admin'), (2, 'Developer'), (3, 'Guest');
INSERT INTO systems (id, sys_name) VALUES (1, 'Prod-DB'), (2, 'CI-CD'), (3, 'Wiki');

INSERT INTO user_roles VALUES (1, 1), (2, 2), (3, 3);
INSERT INTO role_systems VALUES (1, 1), (1, 2), (1, 3), (2, 2), (2, 3), (3, 3);
EOF

    cat <<'EOF' > /home/user/generate_audit.sh
#!/bin/bash
# Flawed query with implicit cross join missing join conditions
sqlite3 -csv /home/user/compliance.db "
SELECT u.name, s.sys_name 
FROM users u, systems s, user_roles ur, role_systems rs 
WHERE u.id = ur.user_id;" > /home/user/fixed_audit_report.csv
EOF
    chmod +x /home/user/generate_audit.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
