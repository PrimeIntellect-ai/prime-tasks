#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app /verify /home/user

    # Generate the schema image
    convert -size 600x200 canvas:white -font DejaVu-Sans -pointsize 18 -draw "text 20,50 'TABLE node_groups: node_id INTEGER PRIMARY KEY, group_id INTEGER' text 20,100 'TABLE links: target_id INTEGER, source_id INTEGER, weight REAL'" /app/schema_info.png

    # Generate raw data
    cat << 'EOF' > /app/raw_data.json
[
  {
    "group_id": 1,
    "nodes": [
      {
        "node_id": 101,
        "incoming_links": [
          {"source_id": 102, "weight": 1.5},
          {"source_id": 201, "weight": 0.5}
        ]
      },
      {
        "node_id": 102,
        "incoming_links": [
          {"source_id": 101, "weight": 2.0}
        ]
      }
    ]
  },
  {
    "group_id": 2,
    "nodes": [
      {
        "node_id": 201,
        "incoming_links": [
          {"source_id": 101, "weight": 3.0}
        ]
      }
    ]
  }
]
EOF

    # Generate oracle program
    cat << 'EOF' > /verify/oracle.py
import sys
import json
import sqlite3

def main():
    db_path = sys.argv[1]
    input_data = sys.stdin.read()
    if not input_data.strip():
        return
    node_ids = json.loads(input_data)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    query = """
    WITH IntraGroupLinks AS (
        SELECT 
            l.target_id,
            l.source_id,
            l.weight,
            DENSE_RANK() OVER (PARTITION BY l.target_id ORDER BY l.weight DESC, l.source_id ASC) as rank
        FROM links l
        JOIN node_groups t_group ON l.target_id = t_group.node_id
        JOIN node_groups s_group ON l.source_id = s_group.node_id
        WHERE t_group.group_id = s_group.group_id AND l.target_id = ?
    )
    SELECT COALESCE(SUM(weight * rank), 0.0)
    FROM IntraGroupLinks;
    """

    results = []
    for nid in node_ids:
        cur.execute(query, (nid,))
        row = cur.fetchone()
        results.append(row[0] if row[0] is not None else 0.0)

    print(json.dumps(results))

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /verify
