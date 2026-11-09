#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/etl

    cat << 'EOF' > /home/user/etl/raw_graph_results.json
[
  {"author_id": "A01", "name": "Alice", "pagerank": 1.2, "trust_score": 0.8},
  {"author_id": "A02", "name": "Bob", "pagerank": 2.5, "trust_score": 0.5},
  {"author_id": "A03", "name": "Charlie", "pagerank": 3.1, "trust_score": 0.9},
  {"author_id": "A04", "name": "Diana", "pagerank": 1.1, "trust_score": 0.95},
  {"author_id": "A05", "name": "Eve", "pagerank": 4.0, "trust_score": 0.7},
  {"author_id": "A06", "name": "Frank", "pagerank": 1.8, "trust_score": 0.65},
  {"author_id": "A07", "name": "Grace", "pagerank": 2.2, "trust_score": 0.4},
  {"author_id": "A08", "name": "Heidi", "pagerank": 3.1, "trust_score": 0.88},
  {"author_id": "A09", "name": "Ivan", "pagerank": 0.5, "trust_score": 0.99},
  {"author_id": "A10", "name": "Judy", "pagerank": 2.7, "trust_score": 0.75},
  {"author_id": "A11", "name": "Mallory", "pagerank": 1.9, "trust_score": 0.61},
  {"author_id": "A12", "name": "Niaj", "pagerank": 3.8, "trust_score": 0.82},
  {"author_id": "A13", "name": "Olivia", "pagerank": 2.9, "trust_score": 0.6},
  {"author_id": "A14", "name": "Peggy", "pagerank": 1.5, "trust_score": 0.9},
  {"author_id": "A15", "name": "Sybil", "pagerank": 0.8, "trust_score": 0.85},
  {"author_id": "A16", "name": "Trent", "pagerank": 4.2, "trust_score": 0.55},
  {"author_id": "A17", "name": "Victor", "pagerank": 3.5, "trust_score": 0.77},
  {"author_id": "A18", "name": "Walter", "pagerank": 1.2, "trust_score": 0.92},
  {"author_id": "A19", "name": "Xavier", "pagerank": 2.1, "trust_score": 0.68},
  {"author_id": "A20", "name": "Yvonne", "pagerank": 3.3, "trust_score": 0.81}
]
EOF

    cat << 'EOF' > /home/user/etl/query_plan.txt
+-----------------------+----------------+------+---------+----------------+
| Operator              | EstimatedRows  | Rows | DbHits  | Memory (Bytes) |
+-----------------------+----------------+------+---------+----------------+
| +ProduceResults       |            150 |  120 |       0 |              0 |
| | +Filter             |            150 |  120 |     500 |          10240 |
| | | +CartesianProduct |         250000 | 8500 |       0 |        1048576 |
| | | | +NodeByLabelScan|            500 |  500 |     501 |           2048 |
| | | | +NodeByLabelScan|            500 |  500 |     501 |           2048 |
+-----------------------+----------------+------+---------+----------------+
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
