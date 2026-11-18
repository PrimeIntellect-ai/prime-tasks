#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 wget curl default-jre
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite Database
    python3 -c "
import sqlite3
import datetime

conn = sqlite3.connect('/home/user/backups.db')
c = conn.cursor()

c.execute('''CREATE TABLE datastores (id INTEGER PRIMARY KEY, name TEXT, uri TEXT)''')
c.execute('''CREATE TABLE backups (id INTEGER PRIMARY KEY, datastore_id INTEGER, timestamp DATETIME, status TEXT, size_bytes INTEGER)''')

datastores = [
    (1, 'users_db', 'http://example.org/UsersDB'),
    (2, 'orders_db', 'http://example.org/OrdersDB'),
    (3, 'logs_db', 'http://example.org/LogsDB')
]
c.executemany('INSERT INTO datastores VALUES (?, ?, ?)', datastores)

backups = [
    (1, 1, '2023-10-01 10:00:00', 'SUCCESS', 5000),
    (2, 1, '2023-10-02 10:00:00', 'SUCCESS', 5200),
    (3, 1, '2023-10-03 10:00:00', 'FAILED', 0),

    (4, 2, '2023-10-01 11:00:00', 'SUCCESS', 10000),
    (5, 2, '2023-10-02 11:00:00', 'SUCCESS', 11000),

    (6, 3, '2023-10-01 12:00:00', 'FAILED', 0),
    (7, 3, '2023-10-02 12:00:00', 'FAILED', 0)
]
c.executemany('INSERT INTO backups VALUES (?, ?, ?, ?, ?)', backups)

conn.commit()
conn.close()
"

    # Create RDF File
    cat << 'EOF' > /home/user/architecture.ttl
@prefix ex: <http://example.org/> .

ex:AuthService ex:dependsOn ex:UsersDB .
ex:BillingService ex:dependsOn ex:AuthService ;
                  ex:dependsOn ex:OrdersDB .
ex:ReportingService ex:dependsOn ex:BillingService ;
                    ex:dependsOn ex:LogsDB .
ex:Frontend ex:dependsOn ex:AuthService ;
            ex:dependsOn ex:ReportingService .
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
