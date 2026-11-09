#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    wget -O /home/user/json.hpp https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp

    cat << 'EOF' > /home/user/backup_query_result.json
{
  "results": [
    {
      "data": [
        {"row": [{"source": "users_db", "target": "auth_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "orders_db", "target": "users_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "inventory_db", "target": "catalog_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "orders_db", "target": "catalog_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "reviews_db", "target": "users_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "payments_db", "target": "users_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "shipping_db", "target": "orders_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "wishlist_db", "target": "catalog_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "recommendation_db", "target": "catalog_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "profile_db", "target": "users_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "analytics_db", "target": "users_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "fraud_db", "target": "payments_db", "type": "DEPENDS_ON"}]},
        {"row": [{"source": "returns_db", "target": "orders_db", "type": "DEPENDS_ON"}]}
      ]
    }
  ]
}
EOF

    chmod -R 777 /home/user
