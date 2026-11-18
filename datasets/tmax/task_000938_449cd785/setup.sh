#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/schema.json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "id": {"type": "integer"},
      "title": {"type": "string"},
      "year": {"type": "integer"},
      "total_citations": {"type": "integer"},
      "indirect_citations": {
        "type": "array",
        "items": {"type": "string"}
      }
    },
    "required": ["id", "title", "year", "total_citations", "indirect_citations"],
    "additionalProperties": false
  }
}
EOF

    sqlite3 /home/user/papers.db << 'EOF'
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER);
CREATE TABLE citations (citing_id INTEGER, cited_id INTEGER);

INSERT INTO papers (id, title, year) VALUES 
(1, 'Root1', 2020),
(2, 'CitesRoot1_A', 2021),
(3, 'CitesRoot1_B', 2021),
(4, 'Root2', 2021),
(5, 'CitesRoot2_A', 2022),
(6, 'CitesRoot2_B', 2022),
(7, 'CitesRoot2_C', 2022),
(8, 'CitesRoot1_A_A', 2022),
(9, 'CitesRoot1_A_B', 2022),
(10, 'Unrelated', 2020);

INSERT INTO citations (citing_id, cited_id) VALUES 
(2, 1),
(3, 1),
(5, 4),
(6, 4),
(7, 4),
(8, 2),
(9, 2);
EOF

    chmod -R 777 /home/user
