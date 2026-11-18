#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate schema.png and CSVs using a Python script
    python3 -c "
import os
from PIL import Image, ImageDraw, ImageFont

# Generate Image
text = '''FINANCIAL GRAPH SCHEMA V2
Allowed Node Types: User, Account, Transaction
Allowed Relations: 
1. User -[OWNS]-> Account
2. Account -[SENDS]-> Transaction
3. Transaction -[RECEIVES]-> Account
TOPOLOGY CONSTRAINTS:
- No Self-Loops allowed.
- No Wash Trading: An Account cannot SEND to a Transaction that RECEIVES into the exact same Account (A -> Tx -> A is strictly forbidden).'''

img = Image.new('RGB', (800, 400), color='white')
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill='black')
img.save('/app/schema.png')

# Generate Clean CSVs
clean_dir = '/app/corpora/clean'
for i in range(1, 11):
    with open(os.path.join(clean_dir, f'clean_{i}.csv'), 'w') as f:
        f.write(f'U{i},User,A{i},Account,OWNS\n')
        f.write(f'A{i},Account,T{i},Transaction,SENDS\n')
        f.write(f'T{i},Transaction,A{i+100},Account,RECEIVES\n')

# Generate Evil CSVs
evil_dir = '/app/corpora/evil'
for i in range(1, 11):
    with open(os.path.join(evil_dir, f'evil_{i}.csv'), 'w') as f:
        if i % 4 == 0:
            # Wash trading
            f.write(f'A{i},Account,T{i},Transaction,SENDS\n')
            f.write(f'T{i},Transaction,A{i},Account,RECEIVES\n')
        elif i % 4 == 1:
            # Self loop
            f.write(f'U{i},User,U{i},User,OWNS\n')
        elif i % 4 == 2:
            # Invalid relation
            f.write(f'U{i},User,A{i},Account,LOVES\n')
        else:
            # Invalid type
            f.write(f'U{i},Alien,A{i},Account,OWNS\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
