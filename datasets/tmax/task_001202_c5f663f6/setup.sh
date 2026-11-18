#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest toml

    mkdir -p /app
    cd /app
    pip3 download --no-binary :all: toml==0.10.2
    tar -xzf toml-0.10.2.tar.gz
    rm toml-0.10.2.tar.gz

    # Introduce the deliberate typo
    sed -i 's/import datetime/import datatime/g' /app/toml-0.10.2/toml/decoder.py

    # Create the oracle script for the verifier
    cat << 'EOF' > /app/oracle_curate
#!/usr/bin/env python3
import sys
import os
import json
import toml

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    target_dir = sys.argv[1]

    artifacts = []
    for root, _, files in os.walk(target_dir):
        for file in files:
            if file.endswith('.manifest'):
                filepath = os.path.join(root, file)
                content = None
                for enc in ['utf-8', 'utf-16le', 'cp1252']:
                    try:
                        with open(filepath, 'r', encoding=enc) as f:
                            content = f.read()
                        break
                    except UnicodeDecodeError:
                        continue

                if content is not None:
                    try:
                        parsed = toml.loads(content)
                        if 'metadata' in parsed:
                            meta = parsed['metadata']
                            if meta.get('status') == 'released':
                                artifacts.append({
                                    "name": meta.get('artifact_name', ''),
                                    "version": meta.get('version', ''),
                                    "arch": meta.get('architecture', '')
                                })
                    except Exception:
                        pass

    artifacts.sort(key=lambda x: x['name'])
    print(json.dumps(artifacts, separators=(',', ':')))

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_curate

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
