#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    cat << 'EOF' > /app/oracle.py
import sqlite3
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db-path', required=True)
    parser.add_argument('--researcher-id', type=int, required=True)
    args = parser.parse_args()

    conn = sqlite3.connect(args.db_path)
    cur = conn.cursor()

    query = """
        SELECT COUNT(DISTINCT w2.researcher_id)
        FROM wrote w1
        JOIN documents d ON w1.document_id = d.id
        JOIN wrote w2 ON d.id = w2.document_id
        WHERE w1.researcher_id = ? 
          AND w2.researcher_id != ?
          AND d.year > 2015
    """
    cur.execute(query, (args.researcher_id, args.researcher_id))
    result = cur.fetchone()[0]
    print(result)

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
import textwrap

text = "DATABASE SCHEMA: Table 'researchers' has column 'id'. Table 'documents' has columns 'id' and 'year'. Bridging table is 'wrote' with columns 'researcher_id' and 'document_id'. GRAPH MAPPING RULES: An edge exists between two researchers if they share a document. IMPORTANT CONSTRAINT: Only count collaborations on documents where the 'year' is strictly greater than 2015. A researcher cannot be their own co-author."

img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
wrapped_text = textwrap.fill(text, width=60)
d.text((10,10), wrapped_text, fill=(0,0,0))
img.save('/app/schema_doc.png')
EOF

    python3 /tmp/make_image.py
    rm /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
