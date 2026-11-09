#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest jsonschema

useradd -m -s /bin/bash user || true

sqlite3 /home/user/citations.db <<EOF
CREATE TABLE papers (id TEXT, title TEXT);
CREATE TABLE citations (source_id TEXT, target_id TEXT);
INSERT INTO papers VALUES ('P1', 'Deep Learning');
INSERT INTO papers VALUES ('P2', 'Neural Networks');
INSERT INTO papers VALUES ('P3', 'Backpropagation');
INSERT INTO papers VALUES ('P4', 'Optimization Methods');
INSERT INTO papers VALUES ('P5', 'Adam Optimizer');

INSERT INTO citations VALUES ('P1', 'P2');
INSERT INTO citations VALUES ('P2', 'P3');
INSERT INTO citations VALUES ('P3', 'P5');
INSERT INTO citations VALUES ('P1', 'P4');
INSERT INTO citations VALUES ('P4', 'P5');
EOF

cat << 'EOF' > /home/user/schema.json
{
  "type": "object",
  "properties": {
    "path_length": {"type": "integer"},
    "path": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": {"type": "string"},
          "title": {"type": "string"}
        },
        "required": ["id", "title"]
      }
    }
  },
  "required": ["path_length", "path"]
}
EOF

chmod -R 777 /home/user
