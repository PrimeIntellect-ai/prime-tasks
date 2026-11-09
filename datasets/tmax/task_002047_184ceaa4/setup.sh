#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/etl_data/events

    # Create SQLite database
    sqlite3 /home/user/etl_data/primary.db <<EOF
CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, signup_date TEXT);
CREATE TABLE orders (order_id INTEGER PRIMARY KEY, customer_id INTEGER, amount DECIMAL, status TEXT);

INSERT INTO customers (id, name, signup_date) VALUES 
(1, 'Alice Smith', '2023-01-15'),
(2, 'Bob Jones', '2023-02-20'),
(3, 'Charlie Brown', '2023-03-10'),
(4, 'Diana Prince', '2023-04-05'),
(5, 'Evan Wright', '2023-05-12');

INSERT INTO orders (order_id, customer_id, amount, status) VALUES 
(101, 1, 150.00, 'completed'),
(102, 1, 50.00, 'completed'),
(103, 2, 300.00, 'completed'),
(104, 3, 400.00, 'completed'),
(105, 4, 1000.00, 'pending'),
(106, 5, 200.00, 'completed'),
(107, 3, 50.00, 'failed'),
(108, 1, 200.00, 'completed');
EOF

    # Create JSON NoSQL files
    cat <<EOF > /home/user/etl_data/events/stream_1.json
{
  "stream_id": "s1",
  "data": {
    "history": [
      {"user_ref": 1, "action": "LOGIN", "timestamp": "2023-06-01"},
      {"user_ref": 1, "action": "GRANT_VIP", "timestamp": "2023-06-02"},
      {"user_ref": 2, "action": "LOGIN", "timestamp": "2023-06-03"}
    ]
  }
}
EOF

    cat <<EOF > /home/user/etl_data/events/stream_2.json
{
  "stream_id": "s2",
  "data": {
    "history": [
      {"user_ref": 3, "action": "GRANT_VIP", "timestamp": "2023-06-04"},
      {"user_ref": 4, "action": "GRANT_VIP", "timestamp": "2023-06-05"},
      {"user_ref": 5, "action": "REVOKE_VIP", "timestamp": "2023-06-06"}
    ]
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
