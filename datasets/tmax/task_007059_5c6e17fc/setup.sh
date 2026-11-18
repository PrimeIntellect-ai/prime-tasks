#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/query_results.csv
Q_101,450,users,15000
Q_102,120,orders,200
Q_103,890,audit_log,500000
Q_101,450,users,15000
Q_104,330,products,8000
Q_105,950,transactions,850000
Q_103,890,audit_log,500000
Q_106,210,sessions,4500
Q_107,670,inventory,32000
Q_108,55,settings,10
Q_109,780,metrics,120000
Q_104,330,products,8000
Q_110,410,events,18000
EOF

    cat << 'EOF' > /tmp/expected_page.json
[
  {"query": {"id": "Q_107"}, "performance": {"time_ms": 670, "scanned": 32000}, "table": "inventory"},
  {"query": {"id": "Q_101"}, "performance": {"time_ms": 450, "scanned": 15000}, "table": "users"},
  {"query": {"id": "Q_110"}, "performance": {"time_ms": 410, "scanned": 18000}, "table": "events"},
  {"query": {"id": "Q_104"}, "performance": {"time_ms": 330, "scanned": 8000}, "table": "products"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
