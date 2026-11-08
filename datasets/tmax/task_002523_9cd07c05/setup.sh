#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/setup_data.py
import csv

customers = [
    (1, "Alice", "Premium"),
    (2, "Bob", "Standard"),
    (3, "Charlie", "Premium"),
    (4, "David", "Standard")
]

products = [
    (101, "Laptop", "Electronics", 1200.00),
    (102, "Mouse", "Electronics", 25.00),
    (103, "Desk", "Furniture", 300.00),
    (104, "Headphones", "Electronics", 150.00)
]

transactions = [
    (1001, 1, 101, "2023-05-14", 1),
    (1002, 2, 102, "2023-06-20", 2),
    (1003, 3, 104, "2023-11-05", 3),
    (1004, 4, 103, "2023-12-01", 1),
    (1005, 1, 102, "2024-01-15", 1),
    (1006, 2, 101, "2022-12-25", 1)
]

with open("/home/user/data/customers.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["customer_id", "name", "segment"])
    writer.writerows(customers)

with open("/home/user/data/products.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["product_id", "name", "category", "price"])
    writer.writerows(products)

with open("/home/user/data/transactions.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["transaction_id", "customer_id", "product_id", "transaction_date", "quantity"])
    writer.writerows(transactions)
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
