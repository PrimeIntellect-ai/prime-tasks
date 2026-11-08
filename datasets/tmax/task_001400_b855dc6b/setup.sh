#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-pil \
        gcc \
        gdb \
        sqlite3 \
        tesseract-ocr \
        libtesseract-dev \
        coreutils

    pip3 install pytest

    # Create directories
    mkdir -p /home/user/build /home/user/data /app

    # Create C helper program
    cat << 'EOF' > /home/user/build/helper_bin.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    char *data_dir = getenv("DATA_DIR");
    if (!data_dir) {
        // Force a segfault
        int *p = NULL;
        *p = 42;
    }
    printf("Helper binary ran successfully.\n");
    return 0;
}
EOF
    gcc -g -o /home/user/build/helper_bin /home/user/build/helper_bin.c
    rm /home/user/build/helper_bin.c

    # Create failing pipeline script
    cat << 'EOF' > /home/user/build/run_pipeline.sh
#!/bin/bash
ulimit -c unlimited
/home/user/build/helper_bin
EOF
    chmod +x /home/user/build/run_pipeline.sh

    # Setup database and image using Python
    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os
from PIL import Image, ImageDraw

# Create image clue
img = Image.new('RGB', (600, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10, 40), "endpoint LIKE '/api/v2/%' AND status = 200", fill='black')
img.save('/app/schema_clue.png')

# Create SQLite database
conn = sqlite3.connect('/home/user/data/metrics.db')
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('PRAGMA synchronous=NORMAL')
conn.execute('CREATE TABLE requests (id INTEGER PRIMARY KEY, endpoint TEXT, status INTEGER, duration REAL)')
conn.execute("INSERT INTO requests (endpoint, status, duration) VALUES ('/api/v2/users', 200, 100.0)")
conn.execute("INSERT INTO requests (endpoint, status, duration) VALUES ('/api/v2/items', 200, 185.2)")
conn.commit()

# Force exit to prevent clean shutdown and keep WAL file
os._exit(0)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Truncate the main database file to simulate corruption
    truncate -s 0 /home/user/data/metrics.db

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
