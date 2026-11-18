#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.jsonl
{"_id": "u1", "profile": {"name": "Alice", "email": "alice@example.com"}}
{"_id": "u2", "profile": {"name": "Bob", "email": "bob@example.com"}}
{"_id": "u3", "profile": {"name": "Charlie", "email": "charlie@example.com"}}
EOF

    cat << 'EOF' > /home/user/data/products.jsonl
{"prod_id": "p1", "details": {"category": "Electronics", "price": 300.0}, "name": "Tablet"}
{"prod_id": "p2", "details": {"category": "Home", "price": 50.0}, "name": "Lamp"}
{"prod_id": "p3", "details": {"category": "Electronics", "price": 150.0}, "name": "Headphones"}
{"prod_id": "p4", "details": {"category": "Toys", "price": 25.0}, "name": "Action Figure"}
EOF

    cat << 'EOF' > /home/user/data/orders.jsonl
{"order_id": "o1", "u_id": "u1", "status": "completed", "items": [{"p_id": "p1", "qty": 2}, {"p_id": "p2", "qty": 1}]}
{"order_id": "o2", "u_id": "u1", "status": "canceled", "items": [{"p_id": "p3", "qty": 1}]}
{"order_id": "o3", "u_id": "u2", "status": "completed", "items": [{"p_id": "p2", "qty": 4}]}
{"order_id": "o4", "u_id": "u3", "status": "completed", "items": [{"p_id": "p3", "qty": 1}, {"p_id": "p4", "qty": 2}]}
EOF

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "user_id": {"type": "string"},
      "name": {"type": "string"},
      "email": {"type": "string", "format": "email"},
      "total_spent": {"type": "number"},
      "electronics_purchased": {
        "type": "array",
        "items": {"type": "string"}
      }
    },
    "required": ["user_id", "name", "email", "total_spent", "electronics_purchased"],
    "additionalProperties": false
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
