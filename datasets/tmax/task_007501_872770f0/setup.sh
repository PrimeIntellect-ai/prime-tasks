#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_pipeline/data
    mkdir -p /home/user/data_pipeline/output

    cd /home/user/data_pipeline
    git config --global init.defaultBranch main
    git config --global user.email "dev@example.com"
    git config --global user.name "Developer"
    git init

    # Commit 1: Add config with secret
    cat << 'EOF' > config.json
{"secret_key": "SUPER_SECRET_99X"}
EOF
    git add config.json
    git commit -m "Initial commit with config"

    # Commit 2: Remove secret
    cat << 'EOF' > config.json
{"secret_key": ""}
EOF
    git add config.json
    git commit -m "Update config: remove secret"

    # Create data files with spaces in names
    cat << 'EOF' > "data/file 1.json"
{"id": 1, "value": "A"}
EOF

    cat << 'EOF' > "data/file 2.json"
{"id": 2, "value": "B"}
EOF

    # Create file 3 with UTF-16LE encoding using Python
    python3 -c '
import json
data = {"id": 3, "value": "C"}
with open("data/file 3 spaces.json", "w", encoding="utf-16le") as f:
    f.write(json.dumps(data))
'

    # Create the buggy build.sh script
    cat << 'EOF' > build.sh
#!/bin/bash
rm -f output/combined.json
# BUG: variables are not quoted, breaks on spaces
for f in data/*.json; do
    python3 process.py $f
done
EOF
    chmod +x build.sh

    # Create the buggy process.py script
    cat << 'EOF' > process.py
import sys
import json
import os

with open('config.json') as f:
    config = json.load(f)

assert config.get("secret_key"), "Missing secret_key in config.json"

input_file = sys.argv[1]
# BUG: Does not handle UTF-16 encoding
with open(input_file, 'r') as f:
    try:
        data = json.load(f)
    except UnicodeDecodeError:
        # Fallback for utf-16 files if the user modifies it this way, 
        # but initially it will just crash on default utf-8 open if not handled
        raise

data['auth'] = config['secret_key']

output_file = 'output/combined.json'
if os.path.exists(output_file):
    with open(output_file, 'r') as f:
        combined = json.load(f)
else:
    combined = []

combined.append(data)

with open(output_file, 'w') as f:
    json.dump(combined, f)
EOF

    chown -R user:user /home/user/data_pipeline
    chmod -R 777 /home/user
