#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest chardet charset-normalizer

    # Create user
    useradd -m -s /bin/bash user || true

    # Create setup script
    cat << 'EOF' > /tmp/setup.py
import os

base_dir = '/home/user/project_dump'
os.makedirs(base_dir, exist_ok=True)
os.makedirs(os.path.join(base_dir, 'module_a'), exist_ok=True)
os.makedirs(os.path.join(base_dir, 'module_b'), exist_ok=True)
os.makedirs(os.path.join(base_dir, 'docs'), exist_ok=True)

# File 1: Windows-1252
content1 = "Résumé of the café project."
with open(os.path.join(base_dir, 'module_a', 'desc.txt'), 'wb') as f:
    f.write(content1.encode('windows-1252'))

# File 2: Shift-JIS (Different content)
content2 = "こんにちは世界"
with open(os.path.join(base_dir, 'module_b', 'notes.txt'), 'wb') as f:
    f.write(content2.encode('shift_jis'))

# File 3: ISO-8859-1 (Same content as File 1)
with open(os.path.join(base_dir, 'module_b', 'desc_backup.txt'), 'wb') as f:
    f.write(content1.encode('iso-8859-1'))

# File 4: readme.txt
content3 = "How to use this system."
with open(os.path.join(base_dir, 'docs', 'ReadMe.txt'), 'wb') as f:
    f.write(content3.encode('utf-8'))

# File 5: Another duplicate of File 1 (UTF-8)
with open(os.path.join(base_dir, 'docs', 'intro.txt'), 'wb') as f:
    f.write(content1.encode('utf-8'))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
