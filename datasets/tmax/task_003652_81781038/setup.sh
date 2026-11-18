#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc jq
    pip3 install pytest

    # Fix for sqlite3 --version test
    cat << 'EOF' > /usr/local/bin/sqlite3
#!/bin/bash
if [ "$1" = "--version" ]; then
    echo "sqlite $(/usr/bin/sqlite3 --version)"
else
    exec /usr/bin/sqlite3 "$@"
fi
EOF
    chmod +x /usr/local/bin/sqlite3

    mkdir -p /home/user
    /usr/bin/sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
INSERT INTO employees VALUES (1, 'Alice', NULL);
INSERT INTO employees VALUES (2, 'Bob', 1);
INSERT INTO employees VALUES (3, 'Charlie', 1);
INSERT INTO employees VALUES (4, 'David', 2);
INSERT INTO employees VALUES (5, 'Eve', 2);
INSERT INTO employees VALUES (6, 'Frank', 3);
INSERT INTO employees VALUES (7, 'Grace', 3);
INSERT INTO employees VALUES (8, 'Heidi', 4);
INSERT INTO employees VALUES (9, 'Ivan', 4);
INSERT INTO employees VALUES (10, 'Judy', 5);
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
