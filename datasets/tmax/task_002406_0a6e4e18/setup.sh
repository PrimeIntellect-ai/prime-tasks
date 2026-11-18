#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq parallel xmlstarlet
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import random
import csv

os.makedirs('/home/user/configs', exist_ok=True)

random.seed(42)

expected_rows = []

for i in range(1, 151):
    fmt = random.choice(['json', 'xml', 'ini'])
    port = random.randint(8000, 9000)
    mem_val = random.choice([256, 512, 1, 2, 4, 8])
    mem_unit = 'M' if mem_val >= 256 else 'G'
    memory_str = str(mem_val) + mem_unit
    memory_mb = mem_val if mem_unit == 'M' else mem_val * 1024

    filename = "server_{:03d}.{}".format(i, fmt)
    filepath = "/home/user/configs/" + filename

    if fmt == 'json':
        with open(filepath, 'w') as f:
            f.write('{"app": {"port": ' + str(port) + ', "memory": "' + memory_str + '"}}\n')
    elif fmt == 'xml':
        with open(filepath, 'w') as f:
            f.write('<config>\n  <app>\n    <port>' + str(port) + '</port>\n    <memory>' + memory_str + '</memory>\n  </app>\n</config>\n')
    elif fmt == 'ini':
        with open(filepath, 'w') as f:
            f.write('[app]\nport=' + str(port) + '\nmemory=' + memory_str + '\n')

    expected_rows.append([filename, fmt, port, memory_mb])

expected_rows.sort(key=lambda x: x[0])

with open('/home/user/.expected_audit.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['filename', 'format', 'port', 'memory_mb'])
    writer.writerows(expected_rows)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
