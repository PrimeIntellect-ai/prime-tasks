#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/etl/input
    mkdir -p /home/user/etl/output

    # Create batch_a.csv
    cat << 'EOF' > /home/user/etl/input/batch_a.csv
delivery_id,user_id,timestamp,amount,currency
d_1001,u_abc,2023-10-01T10:00:00Z,150.00,USD
d_1002,u_xyz,2023-10-01T10:05:00Z,20.50,EUR
d_1003,u_abc,2023-10-01T10:00:00Z,150.00,USD
EOF

    # Create batch_b.json
    cat << 'EOF' > /home/user/etl/input/batch_b.json
[
  {"delivery_id": "d_2001", "user_id": "u_def", "timestamp": "2023-10-01T10:10:00Z", "amount": 99.99, "currency": "USD"},
  {"delivery_id": "d_2002", "user_id": "u_xyz", "timestamp": "2023-10-01T10:05:00Z", "amount": 20.5, "currency": "EUR"},
  {"delivery_id": "d_2003", "user_id": "u_ghi", "timestamp": "2023-10-01T10:15:00Z", "amount": 50.00, "currency": "GBP"}
]
EOF

    # Create batch_c.xml
    cat << 'EOF' > /home/user/etl/input/batch_c.xml
<transactions>
  <transaction>
    <delivery_id>d_3001</delivery_id>
    <user_id>u_def</user_id>
    <timestamp>2023-10-01T10:10:00Z</timestamp>
    <amount>99.99</amount>
    <currency>USD</currency>
  </transaction>
  <transaction>
    <delivery_id>d_3002</delivery_id>
    <user_id>u_jkl</user_id>
    <timestamp>2023-10-01T10:20:00Z</timestamp>
    <amount>200.0</amount>
    <currency>JPY</currency>
  </transaction>
</transactions>
EOF

    # Set permissions
    chmod -R 777 /home/user
