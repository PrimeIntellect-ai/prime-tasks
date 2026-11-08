#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/etl

    cat << 'EOF' > /home/user/data/orders.json
[
  {
    "user_id": "U001",
    "user_name": "Bob Smith",
    "purchases": [
      {
        "product_id": "P992",
        "category": "Books",
        "price": 15.50,
        "quantity": 2
      },
      {
        "product_id": "P114",
        "category": "Electronics",
        "price": 299.00,
        "quantity": 1
      }
    ]
  },
  {
    "user_id": "U002",
    "user_name": "Charlie Brown",
    "purchases": [
      {
        "product_id": "P992",
        "category": "Books",
        "price": 15.50,
        "quantity": 1
      }
    ]
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
