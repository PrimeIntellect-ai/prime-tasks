#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git gawk
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/math_repo
cd /home/user/math_repo
git init
git config user.name "Test User"
git config user.email "test@example.com"

cat << 'EOF' > analyze.py
import sys
import statistics
try:
    with open(sys.argv[1], 'r') as f:
        nums = [float(x) for x in f.read().split()]
        print(statistics.median(nums))
except Exception as e:
    sys.exit(1)
EOF

git add analyze.py
git commit -m "Initial commit"

for i in $(seq 2 200); do
    echo "Commit $i" > README.md
    git add README.md

    if [ "$i" -eq 85 ]; then
        echo '{"API_KEY": "AKIA12345SECRET98765"}' > config.json
        git add config.json
    fi

    if [ "$i" -eq 88 ]; then
        git rm config.json
    fi

    if [ "$i" -eq 142 ]; then
        cat << 'EOF' > analyze.py
import sys
import statistics
import os
# Pre-filter using shell
exit_code = os.system("awk '{print $1}' " + sys.argv[1] + " > /tmp/out.txt 2>/dev/null")
if exit_code != 0:
    sys.exit(1)
with open('/tmp/out.txt', 'r') as f:
    nums = [float(x) for x in f.read().split() if x]
    if not nums: sys.exit(1)
    print(statistics.median(nums))
EOF
        git add analyze.py
    fi

    git commit -m "Commit $i"
done

chmod -R 777 /home/user
