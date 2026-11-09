#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the database
    sqlite3 /home/user/ecommerce.db <<EOF
CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, email TEXT);
CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT, price REAL);
CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT);
CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER);
INSERT INTO customers VALUES (1, 'Alice', 'alice@example.com'), (2, 'Bob', 'bob@example.com'), (3, 'Charlie', 'charlie@example.com');
INSERT INTO products VALUES (1, 'Laptop', 'Electronics', 1000.00), (2, 'Mouse', 'Electronics', 50.00), (3, 'Desk', 'Furniture', 200.00);
INSERT INTO orders VALUES (1, 1, '2023-01-01'), (2, 2, '2023-01-02'), (3, 1, '2023-01-03');
INSERT INTO order_items VALUES (1, 1, 1, 1), (2, 1, 2, 2), (3, 2, 1, 1), (4, 3, 3, 1);
EOF

    # Create vendored framework
    mkdir -p /app/vendored_microframe
    touch /app/vendored_microframe/__init__.py

    cat << 'EOF' > /app/vendored_microframe/server.py
import http.server
import urllib.parse
import json

class MicroframeHandler(http.server.BaseHTTPRequestHandler):
    def parse_query(self, query_string):
        params = {}
        if query_string:
            # Intentional bug: splitting on semicolon instead of ampersand
            pairs = query_string.split(';')
            for pair in pairs:
                if '=' in pair:
                    k, v = pair.split('=', 1)
                    params[urllib.parse.unquote(k)] = urllib.parse.unquote(v)
        return params

    def respond_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
