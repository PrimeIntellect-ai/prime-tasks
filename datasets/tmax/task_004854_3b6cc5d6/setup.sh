#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
node_id,processing_delay
A,0
B,2
C,1
D,3
E,0
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,transit_cost
A,B,5
B,C,2
A,C,10
C,D,4
B,D,8
D,E,1
EOF

    cat << 'EOF' > /home/user/queries.csv
query_id,start_node,end_node
q1,A,D
q2,C,E
q3,A,E
EOF

    cat << 'EOF' > /home/user/expected_results.json
[
  {
    "query_id": "q1",
    "path": ["A", "B", "C", "D"],
    "total_transit_cost": 11,
    "total_delay_cost": 3,
    "total_cost": 14
  },
  {
    "query_id": "q2",
    "path": ["C", "D", "E"],
    "total_transit_cost": 5,
    "total_delay_cost": 3,
    "total_cost": 8
  },
  {
    "query_id": "q3",
    "path": ["A", "B", "C", "D", "E"],
    "total_transit_cost": 12,
    "total_delay_cost": 6,
    "total_cost": 18
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
