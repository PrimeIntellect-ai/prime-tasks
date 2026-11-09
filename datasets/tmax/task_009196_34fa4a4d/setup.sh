#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest chardet

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_app/inputs

    cat << 'EOF' > /home/user/legacy_app/config.ini
[Export]
input_dir = /home/user/legacy_app/inputs
output_file = /home/user/legacy_app/export.csv
target_encoding = UTF-8
format = csv
lock_path = /home/user/legacy_app/export.lock
EOF

    python3 -c "
import os
inputs_dir = '/home/user/legacy_app/inputs'
os.makedirs(inputs_dir, exist_ok=True)

with open(os.path.join(inputs_dir, 'data1.txt'), 'w', encoding='iso-8859-1') as f:
    f.write('Item: Café\nPrice: 12.50\n')

with open(os.path.join(inputs_dir, 'data2.txt'), 'w', encoding='utf-16le') as f:
    f.write('Item: Jalapeño\nPrice: 5.00\n')

with open(os.path.join(inputs_dir, 'data3.txt'), 'w', encoding='utf-8') as f:
    f.write('Item: Apple\nPrice: 1.20\n')
"

    chown -R user:user /home/user/legacy_app
    chmod -R 777 /home/user
