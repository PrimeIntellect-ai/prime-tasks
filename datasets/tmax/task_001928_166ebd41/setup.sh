#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Create directories
mkdir -p /home/user/.github/workflows

# Create legacy Python script
cat << 'EOF' > /home/user/legacy_processor.py
import sys

def process(filepath):
    with open(filepath, 'rb') as f:
        lines = f.readlines()
    for line in lines:
        cleaned = line.strip().replace('"', '')
        print cleaned

if __name__ == "__main__":
    process(sys.argv[1])
EOF

# Create data files with different encodings
echo '"apple",105' > /home/user/data_utf8.csv
echo '"banana",12' >> /home/user/data_utf8.csv

echo '"cherry",45' | iconv -f UTF-8 -t CP1252 > /home/user/data_cp1252.csv
echo '"date",88' | iconv -f UTF-8 -t CP1252 >> /home/user/data_cp1252.csv

echo '"elderberry",3' | iconv -f UTF-8 -t UTF-16LE > /home/user/data_utf16.csv
echo '"fig",200' | iconv -f UTF-8 -t UTF-16LE >> /home/user/data_utf16.csv

# Create baseline
cat << 'EOF' > /home/user/baseline.csv
elderberry,3
banana,12
cherry,45
date,88
apple,105
fig,200
EOF

chmod +x /home/user/legacy_processor.py

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
