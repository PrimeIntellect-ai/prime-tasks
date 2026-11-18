#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3
    pip3 install pytest Pillow

    mkdir -p /app

    python3 -c "
from PIL import Image, ImageDraw
import os

img = Image.new('RGB', (600, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''DB_PRIMARY -> DB_A : 10
DB_PRIMARY -> DB_B : 20
DB_A -> DB_C : 15
DB_B -> DB_C : 5
DB_B -> DB_D : 10
DB_C -> DB_ARCHIVE : 20
DB_D -> DB_ARCHIVE : 30'''
d.text((10,10), text, fill=(0,0,0))
img.save('/app/topology.png')
"

    sqlite3 /app/nodes.db "CREATE TABLE node_stats (node_name TEXT, free_space_gb INTEGER);"
    sqlite3 /app/nodes.db "INSERT INTO node_stats VALUES ('DB_PRIMARY', 2000), ('DB_A', 1000), ('DB_B', 800), ('DB_C', 200), ('DB_D', 600), ('DB_ARCHIVE', 10000);"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
