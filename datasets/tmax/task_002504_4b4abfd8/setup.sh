#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user
cd /home/user

# Create CSV files
cat << 'EOF' > customers.csv
customer_id,region
1,North
2,South
3,East
4,West
EOF

cat << 'EOF' > products.csv
product_id,category
101,Electronics
102,Clothing
103,Home
EOF

cat << 'EOF' > sales.csv
transaction_id,customer_id,product_id,amount
1,1,101,500.0
2,2,102,50.0
3,1,103,100.0
4,3,101,600.0
5,4,102,45.0
6,2,101,150.0
EOF

# Create the buggy Python script
cat << 'EOF' > generate_report.py
import sqlite3
import csv
import json

def load_csv_to_table(cursor, table_name, file_path, columns):
    cursor.execute(f"CREATE TABLE {table_name} ({columns})")
    with open(file_path, 'r') as f:
        reader = csv.reader(f)
        next(reader) # skip header
        cursor.executemany(f"INSERT INTO {table_name} VALUES ({','.join(['?']*len(columns.split(',')))})", reader)

def main():
    conn = sqlite3.connect(':memory:')
    cursor = conn.cursor()

    load_csv_to_table(cursor, 'customers', 'customers.csv', 'customer_id INTEGER, region TEXT')
    load_csv_to_table(cursor, 'products', 'products.csv', 'product_id INTEGER, category TEXT')
    load_csv_to_table(cursor, 'sales', 'sales.csv', 'transaction_id INTEGER, customer_id INTEGER, product_id INTEGER, amount REAL')

    # BUG: Missing join condition for products table, causing an implicit cross join
    query = """
    SELECT c.region, p.category, SUM(s.amount) as total_sales
    FROM sales s, customers c, products p
    WHERE s.customer_id = c.customer_id
    GROUP BY c.region, p.category
    """

    cursor.execute(query)
    results = cursor.fetchall()

    for row in results:
        print(row)

if __name__ == "__main__":
    main()
EOF
chmod +x generate_report.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
