#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas jsonschema

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/customers.csv
customer_id,name
1,Alice
2,Bob
3,Charlie
EOF

    cat << 'EOF' > /home/user/orders.csv
order_id,customer_id,date
101,1,2023-01-01
102,1,2023-01-05
103,2,2023-01-02
EOF

    cat << 'EOF' > /home/user/items.csv
item_id,order_id,price
1001,101,15.50
1002,101,5.00
1003,102,20.00
1004,103,100.00
1005,103,50.00
EOF

    cat << 'EOF' > /home/user/schema.json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "customer_name": { "type": "string" },
      "total_spent": { "type": "number" }
    },
    "required": ["customer_name", "total_spent"],
    "additionalProperties": false
  }
}
EOF

    cat << 'EOF' > /home/user/process_sales.py
import sqlite3
import pandas as pd
import json

# Load CSVs
customers = pd.read_csv('/home/user/customers.csv')
orders = pd.read_csv('/home/user/orders.csv')
items = pd.read_csv('/home/user/items.csv')

# Setup SQLite DB
conn = sqlite3.connect(':memory:')
customers.to_sql('customers', conn, index=False)
orders.to_sql('orders', conn, index=False)
items.to_sql('items', conn, index=False)

# BUGGY QUERY: Missing join condition between orders and items
query = """
SELECT c.name as customer_name, SUM(i.price) as total_spent
FROM customers c, orders o, items i
WHERE c.customer_id = o.customer_id
GROUP BY c.name;
"""

df_result = pd.read_sql_query(query, conn)
print(df_result)
# Missing JSON output and validation logic
EOF

    chmod -R 777 /home/user
