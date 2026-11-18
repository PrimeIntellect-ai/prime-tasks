#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data_processor
cd /home/user/data_processor
git init
git config user.name "Dev"
git config user.email "dev@example.com"

cat << 'EOF' > process.py
import sys
import json

def process(data):
    res = 0
    for item in data.get("items", []):
        val = item.get("val", 0)
        res += val
    return res

if __name__ == "__main__":
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(process(data))
EOF
git add process.py
git commit -m "Initial commit"

for i in $(seq 1 200); do
    if [ $i -eq 137 ]; then
        cat << 'EOF' > process.py
import sys
import json

def process(data):
    res = 0
    for item in data.get("items", []):
        val = item.get("val", 0)
        if val < 0:
            res += 100 / (val + 5)
        else:
            res += val
    return res

if __name__ == "__main__":
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(process(data))
EOF
    else
        echo "# Comment $i" >> process.py
    fi
    git add process.py
    git commit -m "Commit $i"
done

# Generate crash_input.json
cd /home/user
cat << 'EOF' > generate_json.py
import json

items = []
for i in range(1, 101):
    if i == 73:
        items.append({"val": -5, "id": i})
    else:
        items.append({"val": i % 10, "id": i})

with open("crash_input.json", "w") as f:
    json.dump({"items": items}, f, indent=2)
EOF
python3 generate_json.py
rm generate_json.py

chown -R user:user /home/user/data_processor /home/user/crash_input.json
chmod -R 777 /home/user
