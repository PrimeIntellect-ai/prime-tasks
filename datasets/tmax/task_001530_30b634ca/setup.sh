#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev nlohmann-json3-dev sqlite3 python3-pil
    pip3 install pytest

    mkdir -p /app

    sqlite3 /app/data.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, label TEXT, properties TEXT);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER, edge_type TEXT, is_deleted INTEGER);

INSERT INTO nodes VALUES (1, 'User', '{}');
INSERT INTO nodes VALUES (2, 'Product', '{}');
INSERT INTO nodes VALUES (3, 'Category', '{"department": "Electronics"}');
INSERT INTO nodes VALUES (4, 'Category', '{"department": "Clothing"}');
INSERT INTO nodes VALUES (5, 'User', '{}');
INSERT INTO nodes VALUES (6, 'Product', '{}');

-- Active matches
INSERT INTO edges VALUES (1, 2, 'PURCHASED', 0);
INSERT INTO edges VALUES (2, 3, 'BELONGS_TO', 0);

-- Inactive/deleted match (corrupted index might return this)
INSERT INTO edges VALUES (5, 6, 'PURCHASED', 1);
INSERT INTO edges VALUES (6, 3, 'BELONGS_TO', 0);

-- Wrong category
INSERT INTO edges VALUES (1, 6, 'PURCHASED', 0);
INSERT INTO edges VALUES (6, 4, 'BELONGS_TO', 0);

-- Corrupted index
CREATE INDEX idx_edges_active ON edges(source_id) WHERE is_deleted = 0;
EOF

    cat << 'EOF' > /tmp/ground_truth.json
[
  {"user_id": 1, "product_id": 2, "category_id": 3}
]
EOF

    cat << 'EOF' > /tmp/verify.py
import json
import sys

def calculate_f1(pred_path, truth_path):
    try:
        with open(pred_path, 'r') as f:
            preds = json.load(f)
        with open(truth_path, 'r') as f:
            truth = json.load(f)
    except Exception as e:
        print(f"Error reading files: {e}")
        return 0.0

    pred_set = set(tuple(sorted(d.items())) for d in preds)
    truth_set = set(tuple(sorted(d.items())) for d in truth)

    tp = len(pred_set & truth_set)
    fp = len(pred_set - truth_set)
    fn = len(truth_set - pred_set)

    if tp == 0:
        return 0.0

    precision = tp / (tp + fp)
    recall = tp / (tp + fn)
    f1 = 2 * (precision * recall) / (precision + recall)
    return f1

if __name__ == "__main__":
    f1_score = calculate_f1('/app/matches.json', '/tmp/ground_truth.json')
    print(f"F1_SCORE: {f1_score}")
    if f1_score >= 0.95:
        sys.exit(0)
    else:
        sys.exit(1)
EOF

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = """GRAPH MAPPING SCHEMA:
- Nodes table: id (INT), label (VARCHAR), properties (JSON)
- Edges table: source_id (INT), target_id (INT), edge_type (VARCHAR), is_deleted (INT)
- Active Edge Definition: is_deleted = 0. (Warning: corrupted index ignores this flag).
PATTERN TO MATCH:
Find all paths: (User) -[PURCHASED]-> (Product) -[BELONGS_TO]-> (Category)
Where Category has properties containing '"department": "Electronics"'."""
d.text((20, 40), text, fill=(0,0,0))
img.save('/app/schema_mapping.png')
EOF
    python3 /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
