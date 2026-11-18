#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

cat << 'OUTEREOF' > /tmp/setup.sh
#!/bin/bash
mkdir -p /home/user/data_engine
cd /home/user/data_engine

git init
git config user.email "test@example.com"
git config user.name "Test User"

# Create the initial good state
cat << 'EOF' > query.py
def execute_query(q):
    return {"status": "success", "data": [1, 2, 3]}
EOF

cat << 'EOF' > test_query.py
import query
import sys

result = query.execute_query("SELECT * FROM table")
if not result or "data" not in result or len(result["data"]) == 0:
    print("Query failed!")
    sys.exit(1)
print("Query succeeded!")
sys.exit(0)
EOF

git add query.py test_query.py
git commit -m "Initial commit"
git tag v1.0

# Generate 200 commits
for i in {2..200}; do
    if [ $i -eq 142 ]; then
        # Introduce the intermittent bug at commit 142
        cat << 'EOF' > query.py
import time
def execute_query(q):
    # Intermittent failure introduced here
    if int(time.time() * 1000) % 3 == 0:
        return {"status": "error", "data": []}
    return {"status": "success", "data": [1, 2, 3]}
EOF
        git add query.py
        git commit -m "Update query execution engine logic"
    else
        # Unrelated changes
        echo "# Comment $i" >> query.py
        git add query.py
        git commit -m "Refactor: incremental update $i"
    fi
done

git tag v2.0
OUTEREOF

bash /tmp/setup.sh
rm /tmp/setup.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
