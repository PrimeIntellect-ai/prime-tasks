#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 imagemagick fonts-dejavu tesseract-ocr
pip3 install --default-timeout=100 pytest jsonschema pytesseract

mkdir -p /app

sqlite3 /app/knowledge_graph.db <<EOF
CREATE TABLE nodes(id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER, value REAL);
INSERT INTO nodes (id, name, parent_id, value) VALUES 
(1, 'Alpha', NULL, 10.0),
(2, 'Alpha_child1', 1, 40.5),
(3, 'Alpha_child2', 1, 50.0),
(4, 'Beta', NULL, 5.0),
(5, 'Beta_child1', 4, 20.2),
(6, 'Beta_child2', 4, 20.0),
(7, 'Gamma', NULL, 15.0),
(8, 'Gamma_child1', 7, 10.0);
EOF

cat << 'EOF' > /app/output_schema.json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "root_name": {"type": "string"},
      "total_value": {"type": "number"}
    },
    "required": ["root_name", "total_value"],
    "additionalProperties": false
  }
}
EOF

convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
  -draw "text 10,50 'Target Root Nodes: Alpha, Beta, Gamma'" \
  -draw "text 10,80 'Minimum Aggregate Value: 42.5'" \
  /app/query_criteria.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
