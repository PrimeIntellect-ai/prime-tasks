#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the SQLite database
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random
from datetime import datetime, timedelta

conn = sqlite3.connect('/home/user/ecommerce.db')
c = conn.cursor()

c.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, order_date DATE)')
c.execute('CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER)')
c.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT, price REAL)')

random.seed(42)

users = [(i, f'User {i}') for i in range(1, 1001)]
c.executemany('INSERT INTO users VALUES (?, ?)', users)

categories = [f'Category {i}' for i in range(1, 11)]
products = [(i, f'Product {i}', random.choice(categories), round(random.uniform(5.0, 100.0), 2)) for i in range(1, 201)]
c.executemany('INSERT INTO products VALUES (?, ?, ?, ?)', products)

orders = [(i, random.randint(1, 1000), (datetime.now() - timedelta(days=random.randint(0, 365))).date()) for i in range(1, 5001)]
c.executemany('INSERT INTO orders VALUES (?, ?, ?)', orders)

order_items = [(i, random.randint(1, 5000), random.randint(1, 200), random.randint(1, 5)) for i in range(1, 15001)]
c.executemany('INSERT INTO order_items VALUES (?, ?, ?, ?)', order_items)

conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    # Setup the oracle script
    mkdir -p /oracle
    cat << 'EOF' > /oracle/run_report_oracle.sh
#!/bin/bash
USER_ID=$1
sqlite3 /home/user/ecommerce.db <<DBEOF
.mode csv
SELECT p.category, printf('%.2f', SUM(p.price * oi.quantity)) as total_spend
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
WHERE u.id = ${USER_ID}
GROUP BY p.category
ORDER BY SUM(p.price * oi.quantity) DESC, p.category ASC;
DBEOF
EOF
    chmod +x /oracle/run_report_oracle.sh

    # Vendor mo and apply perturbation
    mkdir -p /app/mo-3.0.2
    curl -sSL https://raw.githubusercontent.com/tests-always-included/mo/3.0.2/mo -o /app/mo-3.0.2/mo

    # Try replacing existing shopt, otherwise force it on line 12
    sed -i 's/shopt -s extglob/#shopt -s extglob/g' /app/mo-3.0.2/mo
    if ! grep -q "#shopt -s extglob" /app/mo-3.0.2/mo; then
        sed -i '12s/.*/#shopt -s extglob/' /app/mo-3.0.2/mo
    fi
    chmod +x /app/mo-3.0.2/mo

    chmod -R 777 /home/user
