#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/relational_deps.csv
db,depends_on
user_db,auth_db
profile_db,user_db
billing_db,user_db
analytics_db,billing_db
EOF

    cat << 'EOF' > /home/user/doc_deps.json
[
  {"db": "notification_db", "requires": ["profile_db"]},
  {"db": "recommendation_db", "requires": ["user_db", "analytics_db"]},
  {"db": "auth_db", "requires": ["root_ca_db"]},
  {"db": "unrelated_db", "requires": ["some_other_db"]}
]
EOF

    chmod -R 777 /home/user
