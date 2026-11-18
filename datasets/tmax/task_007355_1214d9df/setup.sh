#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/orders.json
[
  {
    "order_id": "O001",
    "order_date": "2023-10-01T10:00:00Z",
    "user": {
      "user_id": "U101",
      "name": "Alice Smith",
      "email": "alice@example.com"
    },
    "items": [
      {
        "product": {
          "product_id": "P001",
          "name": "Laptop",
          "category": "Electronics",
          "price": 1000.00
        },
        "quantity": 1
      },
      {
        "product": {
          "product_id": "P002",
          "name": "Mouse",
          "category": "Electronics",
          "price": 50.00
        },
        "quantity": 2
      }
    ]
  },
  {
    "order_id": "O002",
    "order_date": "2023-10-02T11:30:00Z",
    "user": {
      "user_id": "U102",
      "name": "Bob Jones",
      "email": "bob@example.com"
    },
    "items": [
      {
        "product": {
          "product_id": "P003",
          "name": "Desk Chair",
          "category": "Furniture",
          "price": 150.00
        },
        "quantity": 2
      },
      {
        "product": {
          "product_id": "P001",
          "name": "Laptop",
          "category": "Electronics",
          "price": 1000.00
        },
        "quantity": 1
      }
    ]
  },
  {
    "order_id": "O003",
    "order_date": "2023-10-03T09:15:00Z",
    "user": {
      "user_id": "U103",
      "name": "Charlie Brown",
      "email": "charlie@example.com"
    },
    "items": [
      {
        "product": {
          "product_id": "P004",
          "name": "Headphones",
          "category": "Electronics",
          "price": 200.00
        },
        "quantity": 3
      },
      {
        "product": {
          "product_id": "P005",
          "name": "Coffee Table",
          "category": "Furniture",
          "price": 300.00
        },
        "quantity": 1
      }
    ]
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
