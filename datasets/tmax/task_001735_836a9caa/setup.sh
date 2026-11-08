#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > customers.csv
customer_id,name
1,Alice
2,Bob
3,Charlie
4,Diana
EOF

    cat << 'EOF' > orders.csv
order_id,customer_id,order_date
101,1,2023-01-01
102,1,2023-01-05
103,2,2023-01-02
104,4,2023-01-10
105,4,2023-01-12
EOF

    cat << 'EOF' > order_items.csv
item_id,order_id,product_id,price,quantity
1001,101,P1,10.0,2
1002,101,P2,15.0,1
1003,102,P1,10.0,1
1004,103,P3,50.0,1
1005,104,P1,10.0,3
1006,105,P4,5.0,4
EOF

    cat << 'EOF' > report_generator.py
import sqlite3
import pandas as pd

conn = sqlite3.connect(':memory:')

customers = pd.read_csv('/home/user/customers.csv')
orders = pd.read_csv('/home/user/orders.csv')
order_items = pd.read_csv('/home/user/order_items.csv')

customers.to_sql('customers', conn, index=False)
orders.to_sql('orders', conn, index=False)
order_items.to_sql('order_items', conn, index=False)

# BUGGY QUERY
query = """
SELECT c.customer_id, SUM(oi.price * oi.quantity) as total_revenue
FROM customers c, orders o, order_items oi
GROUP BY c.customer_id
"""

df = pd.read_sql_query(query, conn)
df.to_csv('/home/user/customer_revenue_rank.csv', index=False)
EOF

    chmod +x report_generator.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
