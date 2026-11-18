#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    # Create customers.csv
    cat << 'EOF' > /home/user/data/customers.csv
customer_id,first_name,last_name,region
1,Alice,Smith,North
2,Bob,Jones,South
3,Charlie,Brown,East
4,Diana,Prince,West
EOF

    # Create sales.sqlite
    sqlite3 /home/user/data/sales.sqlite << 'EOF'
CREATE TABLE order_history (
    id INTEGER PRIMARY KEY,
    order_id INTEGER,
    customer_id INTEGER,
    amount DECIMAL,
    status TEXT,
    updated_at DATETIME
);

INSERT INTO order_history (order_id, customer_id, amount, status, updated_at) VALUES
(101, 1, 250.50, 'PENDING', '2023-01-01 10:00:00'),
(101, 1, 250.50, 'SHIPPED', '2023-01-02 11:00:00'),
(102, 1, 100.00, 'PENDING', '2023-01-03 09:00:00'),
(102, 1, 100.00, 'CANCELLED', '2023-01-04 10:00:00'),
(103, 2, 500.00, 'PENDING', '2023-01-01 08:00:00'),
(104, 3, 50.00, 'PENDING', '2023-01-05 12:00:00'),
(104, 3, 50.00, 'SHIPPED', '2023-01-06 12:00:00'),
(105, 3, 75.25, 'PENDING', '2023-01-07 14:00:00');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
