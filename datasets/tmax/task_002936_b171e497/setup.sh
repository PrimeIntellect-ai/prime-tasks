#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    cat << 'EOF' > /tmp/setup_data.py
import os
import sqlite3
from PIL import Image, ImageDraw

# Generate image
text = "URGENT COMPLIANCE AUDIT: Flag any network where a Politically Exposed Person (type='PEP') connects to a Shell company (type='Shell') via a chain of 'owns' or 'transfers_to' relations of depth 1 to 3, AND that Shell company transfers funds (rel_type='transfers_to') to an entity in a HighRisk jurisdiction (jurisdiction='HighRisk'). Ensure you index relations on source and target."
img = Image.new('RGB', (1200, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/compliance_memo.png')

def create_db(path, is_evil):
    conn = sqlite3.connect(path)
    c = conn.cursor()
    c.execute("CREATE TABLE entities (id INTEGER PRIMARY KEY, type TEXT, jurisdiction TEXT)")
    c.execute("CREATE TABLE relations (source INTEGER, target INTEGER, rel_type TEXT, amount REAL)")

    # Insert noise
    for i in range(1, 100):
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (i, 'Corp', 'Standard'))
    for i in range(1, 90):
        c.execute("INSERT INTO relations (source, target, rel_type, amount) VALUES (?, ?, ?, ?)", (i, i+1, 'owns', 100.0))

    # Insert specific pattern
    start_id = 1000
    if is_evil:
        # PEP
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id, 'PEP', 'Standard'))
        # Path of length 2
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id+1, 'Corp', 'Standard'))
        c.execute("INSERT INTO relations (source, target, rel_type, amount) VALUES (?, ?, ?, ?)", (start_id, start_id+1, 'owns', 100.0))
        # Shell
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id+2, 'Shell', 'Standard'))
        c.execute("INSERT INTO relations (source, target, rel_type, amount) VALUES (?, ?, ?, ?)", (start_id+1, start_id+2, 'transfers_to', 100.0))
        # HighRisk
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id+3, 'Corp', 'HighRisk'))
        c.execute("INSERT INTO relations (source, target, rel_type, amount) VALUES (?, ?, ?, ?)", (start_id+2, start_id+3, 'transfers_to', 100.0))
    else:
        # PEP
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id, 'PEP', 'Standard'))
        # Path of length 4 (too long)
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id+1, 'Corp', 'Standard'))
        c.execute("INSERT INTO relations (source, target, rel_type, amount) VALUES (?, ?, ?, ?)", (start_id, start_id+1, 'owns', 100.0))
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id+2, 'Corp', 'Standard'))
        c.execute("INSERT INTO relations (source, target, rel_type, amount) VALUES (?, ?, ?, ?)", (start_id+1, start_id+2, 'owns', 100.0))
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id+3, 'Corp', 'Standard'))
        c.execute("INSERT INTO relations (source, target, rel_type, amount) VALUES (?, ?, ?, ?)", (start_id+2, start_id+3, 'owns', 100.0))
        # Shell
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id+4, 'Shell', 'Standard'))
        c.execute("INSERT INTO relations (source, target, rel_type, amount) VALUES (?, ?, ?, ?)", (start_id+3, start_id+4, 'transfers_to', 100.0))
        # HighRisk
        c.execute("INSERT INTO entities (id, type, jurisdiction) VALUES (?, ?, ?)", (start_id+5, 'Corp', 'HighRisk'))
        c.execute("INSERT INTO relations (source, target, rel_type, amount) VALUES (?, ?, ?, ?)", (start_id+4, start_id+5, 'transfers_to', 100.0))

    conn.commit()
    conn.close()

for i in range(1, 6):
    create_db(f'/app/corpora/evil/evil_{i}.db', True)
    create_db(f'/app/corpora/clean/clean_{i}.db', False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
