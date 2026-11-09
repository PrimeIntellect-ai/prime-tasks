#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sales.csv
sale_id,product_id,amount,date
1,101,500.0,2023-01-01
2,102,150.0,2023-01-02
3,101,500.0,2023-01-03
4,103,99.9,2023-01-04
EOF

    cat << 'EOF' > /home/user/products.csv
id,name,category,price
101,Laptop,Electronics,500.0
102,Headphones,Electronics,150.0
103,Coffee Mug,Kitchen,15.0
EOF

    mkdir -p /app/pylitecsv-1.0.0/pylitecsv

    cat << 'EOF' > /app/pylitecsv-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name="pylitecsv",
    version="1.0.0",
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/pylitecsv-1.0.0/pylitecsv/__init__.py
from .engine import QueryEngine
EOF

    cat << 'EOF' > /app/pylitecsv-1.0.0/pylitecsv/engine.py
import csv

class QueryEngine:
    def read_csv(self, filepath):
        with open(filepath, mode='r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            return list(reader)

    def inner_join(self, left, right, left_key, right_key):
        # BUG: No condition check, acts as a cross join
        return [{**l, **r} for l in left for r in right]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
