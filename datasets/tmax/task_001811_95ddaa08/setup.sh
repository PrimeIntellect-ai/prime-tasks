#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick sqlite3 fonts-dejavu
    pip3 install pytest

    mkdir -p /app

    # Create the Image Fixture
    convert -background white -fill black -font DejaVu-Sans -pointsize 36 label:"BATCH-77A" /app/run_label.png

    # Generate the SQLite Database
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/app/etl_data.db')
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE nodes (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    metric_value INTEGER
)
''')

nodes = [(1, None, random.randint(10, 100))]
for i in range(2, 501):
    parent = random.choice(range(1, i))
    val = random.randint(10, 100)
    nodes.append((i, parent, val))

cursor.executemany('INSERT INTO nodes (id, parent_id, metric_value) VALUES (?, ?, ?)', nodes)

cursor.execute('CREATE INDEX idx_parent ON nodes(parent_id)')
conn.commit()

cursor.execute("PRAGMA writable_schema = 1;")
cursor.execute("UPDATE sqlite_master SET sql = 'CREATE INDEX idx_parent ON nodes(metric_value)' WHERE name = 'idx_parent';")
cursor.execute("PRAGMA writable_schema = 0;")
conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    # Create the Oracle Script
    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
NODE_ID=$1
BATCH="BATCH-77A"

sqlite3 /app/etl_data.db "REINDEX;"

QUERY="
WITH RECURSIVE
  subtree(id, metric_value, depth) AS (
    SELECT id, metric_value, 0 FROM nodes WHERE id = $NODE_ID
    UNION ALL
    SELECT n.id, n.metric_value, s.depth + 1
    FROM nodes n
    JOIN subtree s ON n.parent_id = s.id
  )
SELECT SUM(metric_value), MAX(depth) FROM subtree;
"

RESULT=$(sqlite3 /app/etl_data.db "$QUERY")
SUM=$(echo "$RESULT" | cut -d'|' -f1)
DEPTH=$(echo "$RESULT" | cut -d'|' -f2)

if [ -z "$SUM" ]; then
    SUM=0
    DEPTH=0
fi

echo "[$BATCH] Node $NODE_ID -> Total: $SUM, MaxDepth: $DEPTH"
EOF
    chmod +x /app/oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
