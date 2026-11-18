#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/app/db
    mkdir -p /home/user/app/src
    mkdir -p /home/user/app/logs
    mkdir -p /home/user/app/output

    # Create the SQLite database
    python3 -c "
import sqlite3
conn = sqlite3.connect('/home/user/app/db/data.db')
cursor = conn.cursor()
cursor.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, status TEXT)')
cursor.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL)')
users = [(1, 'Alice', 'active'), (2, 'Bob', 'inactive'), (3, 'Charlie', 'active'), (4, 'Diana', 'active')]
transactions = [(1, 1, 50.0), (2, 1, 100.5), (3, 2, 200.0), (4, 4, 30.0), (5, 4, 15.0)]
cursor.executemany('INSERT INTO users VALUES (?, ?, ?)', users)
cursor.executemany('INSERT INTO transactions VALUES (?, ?, ?)', transactions)
conn.commit()
conn.close()
"

    # Create broken requirements.txt
    cat << 'EOF' > /home/user/app/requirements.txt
python-dateutil==2.8.2
fake-broken-package-999
EOF

    # Create the buggy Python script
    cat << 'EOF' > /home/user/app/src/process_data.py
import sqlite3
import json
import logging
import os

logging.basicConfig(filename='/home/user/app/logs/process.log', level=logging.DEBUG)

def main():
    try:
        logging.info("Connecting to database")
        conn = sqlite3.connect('/home/user/app/db/data.db')
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        # Bug 1: LEFT JOIN creates a row for Charlie with total=None
        query = """
        SELECT users.name, SUM(transactions.amount) as total 
        FROM users 
        LEFT JOIN transactions ON users.id = transactions.user_id 
        WHERE users.status = 'active' 
        GROUP BY users.name
        """
        cursor.execute(query)
        rows = cursor.fetchall()

        results = []
        for row in rows:
            logging.debug(f"Processing row: {dict(row)}")
            # Bug 2: Crash when row['total'] is None (for Charlie)
            if row['total'] > 0:
                results.append({"name": row['name'], "total": row['total']})

        # Bug 3: Not sorted by total descending

        with open('/home/user/app/output/results.json', 'w') as f:
            json.dump(results, f, indent=2)

        logging.info("Processing complete")
    except Exception as e:
        logging.error("Error during processing", exc_info=True)
        raise

if __name__ == "__main__":
    main()
EOF

    # Create run script
    cat << 'EOF' > /home/user/app/run.sh
#!/bin/bash

cd /home/user/app

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate
pip install -r requirements.txt
python src/process_data.py
EOF

    chmod +x /home/user/app/run.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
