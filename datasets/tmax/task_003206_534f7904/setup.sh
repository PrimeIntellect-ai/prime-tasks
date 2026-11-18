#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential pkg-config libssl-dev
    pip3 install pytest

    # Install Rust system-wide
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo
    export PATH="/opt/cargo/bin:$PATH"

    mkdir -p /home/user
    cd /home/user

    # Create SQLite DB
    sqlite3 /home/user/employees.db <<EOF
CREATE TABLE employee (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
CREATE TABLE employee_roles (emp_id INTEGER, role_uri TEXT);
INSERT INTO employee VALUES (1, 'Alice', 'Engineering');
INSERT INTO employee VALUES (2, 'Bob', 'Contractor');
INSERT INTO employee VALUES (3, 'Charlie', 'Contractor');
INSERT INTO employee VALUES (4, 'Dave', 'Contractor');
INSERT INTO employee VALUES (5, 'Eve', 'Contractor');

INSERT INTO employee_roles VALUES (1, 'http://example.org/role/Admin');
INSERT INTO employee_roles VALUES (2, 'http://example.org/role/Guest');
INSERT INTO employee_roles VALUES (3, 'http://example.org/role/TempDev');
INSERT INTO employee_roles VALUES (4, 'http://example.org/role/Vendor');
INSERT INTO employee_roles VALUES (5, 'http://example.org/role/SuperVendor');
EOF

    # Create Turtle File
    cat << 'EOF' > /home/user/resources.ttl
@prefix ex: <http://example.org/> .
@prefix role: <http://example.org/role/> .

role:Admin ex:canRead ex:CustomerData .
role:TempDev ex:inheritsFrom role:Dev .
role:Dev ex:canRead ex:CustomerData .
role:Vendor ex:canRead ex:PublicData .
role:Guest ex:inheritsFrom role:Vendor .
role:SuperVendor ex:inheritsFrom role:Vendor .
role:SuperVendor ex:inheritsFrom role:Admin .
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
