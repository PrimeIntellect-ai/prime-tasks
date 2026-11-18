#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    mkdir -p /app
    cd /app
    wget -q https://files.pythonhosted.org/packages/source/s/simplejson/simplejson-3.19.1.tar.gz
    tar -xzf simplejson-3.19.1.tar.gz
    rm simplejson-3.19.1.tar.gz

    # Apply perturbation to decoder.py
    cat << 'EOF' > patch.py
import sys
file_path = "/app/simplejson-3.19.1/simplejson/decoder.py"
with open(file_path, "r") as f:
    content = f.read()

# Introduce infinite loop on expecting property name
target = 'raise JSONDecodeError("Expecting property name enclosed in double quotes", s, end)'
replacement = 'pairs.append((None, None)); continue'
content = content.replace(target, replacement)

with open(file_path, "w") as f:
    f.write(content)
EOF
    python3 patch.py
    rm patch.py

    # Create corrupted samples
    cat << 'EOF' > /app/corrupted_samples.txt
{"a": 1, 
{"test": "value", "b": 
{"incomplete": 
EOF

    # Create oracle script
    cat << 'EOF' > /usr/local/bin/oracle_parse_fuzz.py
#!/usr/bin/env python3
import sys
import json

def main():
    data = sys.stdin.read()
    try:
        json.loads(data)
        print("SUCCESS")
    except json.JSONDecodeError:
        print("ERROR")
    except Exception:
        print("ERROR")

if __name__ == '__main__':
    main()
EOF
    chmod +x /usr/local/bin/oracle_parse_fuzz.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
