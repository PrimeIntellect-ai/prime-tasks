#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create oracle parser
    mkdir -p /opt
    cat << 'EOF' > /opt/oracle_parser
#!/usr/bin/env python3
import sys

def parse(line):
    parts = line.split(',')
    if len(parts) != 2:
        return "INVALID"
    try:
        lat = float(parts[0].strip())
        lon = float(parts[1].strip())
        return f"({lat}, {lon})"
    except ValueError:
        return "INVALID"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(parse(sys.argv[1]))
    else:
        print("INVALID")
EOF
    chmod +x /opt/oracle_parser

    # Create git repo
    mkdir -p /home/user/geoparse-repo
    cd /home/user/geoparse-repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > parser.py
def parse_line(line):
    parts = line.split(',')
    if len(parts) != 2:
        return "INVALID"
    try:
        lat = float(parts[0].strip())
        lon = float(parts[1].strip())
        return f"({lat}, {lon})"
    except ValueError:
        return "INVALID"
EOF
    git add parser.py
    git commit -m "Initial commit"

    for i in $(seq 2 149); do
        echo "# commit $i" >> dummy.txt
        git add dummy.txt
        git commit -m "Commit $i"
    done

    cat << 'EOF' > parser.py
def parse_line(line):
    parts = line.split(',')
    if len(parts) != 2:
        return "INVALID"
    try:
        lat_str = parts[0]
        lon_str = parts[1]
        lat, lon = round(float(lat_str), 4), round(float(lon_str), 4)
        return f"({lat}, {lon})"
    except ValueError:
        return "INVALID"
EOF
    git add parser.py
    git commit -m "Commit 150: Update parsing logic"

    for i in $(seq 151 200); do
        echo "# commit $i" >> dummy.txt
        git add dummy.txt
        git commit -m "Commit $i"
    done

    # Create vendored package
    mkdir -p /app/geoparse
    cp /home/user/geoparse-repo/parser.py /app/geoparse/parser.py

    chmod -R 777 /home/user
