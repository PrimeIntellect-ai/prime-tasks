#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/slow_queries.json
[
  {"qid": "Q001", "exec_time_ms": 1500},
  {"qid": "Q002", "exec_time_ms": 400},
  {"qid": "Q003", "exec_time_ms": 3200},
  {"qid": "Q004", "exec_time_ms": 800},
  {"qid": "Q005", "exec_time_ms": 5500},
  {"qid": "Q006", "exec_time_ms": 1050},
  {"qid": "Q007", "exec_time_ms": 999}
]
EOF

    cat << 'EOF' > /home/user/table_locks.csv
query_id,table_name,lock_type
Q001,users,EXCLUSIVE
Q001,orders,SHARED
Q002,products,SHARED
Q003,users,EXCLUSIVE
Q003,inventory,EXCLUSIVE
Q003,orders,SHARED
Q004,orders,EXCLUSIVE
Q005,users,SHARED
Q005,logs,EXCLUSIVE
Q006,inventory,EXCLUSIVE
Q007,users,EXCLUSIVE
EOF

    chmod -R 777 /home/user
