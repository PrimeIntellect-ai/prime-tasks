#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
    pip3 install pytest

    mkdir -p /home/user/research_data
    mkdir -p /home/user/extracted_code

    # Create temporary files to archive
    mkdir -p /tmp/dataset1/python_scripts
    mkdir -p /tmp/dataset2/js_scripts
    mkdir -p /tmp/junk

    # Write some python files
    cat << 'EOF' > /tmp/dataset1/python_scripts/main.py
import os
import sys

def main():
    print("Hello World")
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF

    cat << 'EOF' > /tmp/dataset1/python_scripts/utils.py
def add(a, b):
    return a + b
EOF

    # Write index.csv
    cat << 'EOF' > /tmp/dataset1/index.csv
id,filename,language
1,main.py,python
2,utils.py,python
3,app.js,javascript
EOF

    # Add padding to make the dataset1 archive > 10KB
    dd if=/dev/urandom of=/tmp/dataset1/padding.dat bs=1K count=15 2>/dev/null

    # Create dataset1 tar.gz
    cd /tmp/dataset1 && tar -czf /home/user/research_data/dataset1.tar.gz .

    # Write some js files
    cat << 'EOF' > /tmp/dataset2/js_scripts/app.js
console.log("App starting...");
function init() {
    let x = 10;
    let y = 20;
    return x + y;
}
init();
EOF

    # Add padding to dataset2
    dd if=/dev/urandom of=/tmp/dataset2/padding.dat bs=1K count=15 2>/dev/null

    # Create dataset2 zip
    cd /tmp/dataset2 && zip -r /home/user/research_data/dataset2.zip . >/dev/null

    # Create a junk archive < 10KB
    cat << 'EOF' > /tmp/junk/ignored.py
# This should not be extracted
print("Junk")
EOF
    cd /tmp/junk && tar -czf /home/user/research_data/junk.tar.gz .

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
