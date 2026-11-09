#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow

    mkdir -p /home/user/pipeline
    cat << 'EOF' > /home/user/pipeline/ingest.py
import os
import sys
import sqlite3
from concurrent.futures import ThreadPoolExecutor

DB_PATH = '/home/user/pipeline/metadata.db'

def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE IF NOT EXISTS images (filename TEXT PRIMARY KEY, status TEXT)")
    conn.commit()
    conn.close()

def process_file(filename):
    # Bug 1: Unsafe shell execution (breaks on spaces)
    res = os.system(f"file {filename} > /dev/null 2>&1")
    status = "valid" if res == 0 else "invalid"

    # Bug 2: Race condition / Intermittent failure on DB write (SQLite default timeout/concurrency issue)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(f"INSERT INTO images (filename, status) VALUES ('{filename}', '{status}')")
        conn.commit()
    except sqlite3.OperationalError:
        pass # Silently fails on locked DB
    finally:
        conn.close()

if __name__ == "__main__":
    init_db()
    directory = sys.argv[1]
    files = [os.path.join(directory, f) for f in os.listdir(directory)]
    with ThreadPoolExecutor(max_workers=4) as executor:
        executor.map(process_file, files)
EOF

    mkdir -p /app/corpora
    cat << 'EOF' > /app/corpora/evil_filenames.txt
file with spaces.png
my_image.png;rm -rf /
../../etc/passwd.png
image.sh
EOF

    cat << 'EOF' > /app/corpora/clean_filenames.txt
valid_image_123.png
photo-456.jpg
cat_picture.jpeg
EOF

    # Generate the screenshot using Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color = (0, 0, 0))
d = ImageDraw.Draw(img)
d.text((10,40), 'Error in Batch ID: BATCH-77A90X', fill=(255,255,255))
img.save('/app/ticket_8819_screenshot.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
