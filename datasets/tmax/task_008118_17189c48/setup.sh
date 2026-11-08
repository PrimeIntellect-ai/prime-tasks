#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/replication_graph.json
{
  "nodes": [
    {"id": "db1", "name": "users_db"},
    {"id": "db2", "name": "orders_db"},
    {"id": "db3", "name": "inventory_db"},
    {"id": "db4", "name": "analytics_db"},
    {"id": "db5", "name": "logs_db"}
  ],
  "edges": [
    {"source": "db1", "target": "db2"},
    {"source": "db1", "target": "db4"},
    {"source": "db2", "target": "db4"},
    {"source": "db3", "target": "db1"},
    {"source": "db3", "target": "db2"},
    {"source": "db3", "target": "db5"},
    {"source": "db3", "target": "db4"},
    {"source": "db5", "target": "db4"}
  ]
}
EOF

    cat << 'EOF' > /home/user/backup_query_plan.txt
Limit  (cost=100.00..105.00 rows=10 width=8) (actual time=0.500..0.505 rows=10 loops=1)
  ->  Sort  (cost=100.00..102.00 rows=1000 width=8) (actual time=0.490..0.495 rows=10 loops=1)
        Sort Key: backup_logs.timestamp DESC
        ->  Hash Join  (cost=50.00..80.00 rows=1000 width=8) (actual time=0.200..0.350 rows=100 loops=1)
              Hash Cond: (backup_logs.db_id = databases.id)
              ->  Seq Scan on backup_logs  (cost=0.00..20.00 rows=10000 width=4) (actual time=0.010..0.150 rows=10000 loops=1)
              ->  Hash  (cost=45.00..45.00 rows=500 width=4) (actual time=0.180..0.180 rows=500 loops=1)
                    ->  Seq Scan on databases  (cost=0.00..45.00 rows=500 width=4) (actual time=0.050..0.170 rows=500 loops=1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
