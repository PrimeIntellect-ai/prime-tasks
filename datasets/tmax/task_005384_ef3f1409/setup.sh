#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest jsonschema

mkdir -p /home/user/data /home/user/scripts /home/user/output

cat << 'EOF' > /home/user/scripts/bad_query.sql
SELECT a.name, p.year, COUNT(p.paper_id) as yearly_papers
FROM Authors a, Papers p, Author_Paper ap
GROUP BY a.name, p.year;
EOF

cat << 'EOF' > /home/user/data/graph_schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "nodes": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": {"type": "string"},
          "type": {"type": "string", "enum": ["Author", "Paper"]},
          "label": {"type": "string"}
        },
        "required": ["id", "type", "label"]
      }
    },
    "edges": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "source": {"type": "string"},
          "target": {"type": "string"},
          "relation": {"type": "string", "enum": ["AUTHORED"]}
        },
        "required": ["source", "target", "relation"]
      }
    }
  },
  "required": ["nodes", "edges"]
}
EOF

sqlite3 /home/user/data/research.db << 'EOF'
CREATE TABLE Authors (author_id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE Papers (paper_id INTEGER PRIMARY KEY, title TEXT, year INTEGER);
CREATE TABLE Author_Paper (author_id INTEGER, paper_id INTEGER);

INSERT INTO Authors VALUES (1, 'Alice'), (2, 'Bob');
INSERT INTO Papers VALUES (101, 'AI Basics', 2020), (102, 'Advanced ML', 2021), (103, 'Deep Learning', 2021);
INSERT INTO Author_Paper VALUES (1, 101), (1, 102), (2, 102), (2, 103);
EOF

cat << 'EOF' > /home/user/data/metadata.jsonl
{"paper_id": 101, "tags": ["AI", "Intro"]}
{"paper_id": 102, "tags": ["AI", "ML", "Advanced"]}
{"paper_id": 103, "tags": ["ML", "Neural Networks"]}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
