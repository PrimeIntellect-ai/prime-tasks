#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

mkdir -p /home/user/repo
cd /home/user/repo
git init
git config user.email "test@example.com"
git config user.name "Test User"

# Write dataset
cat << 'EOF' > /home/user/data.txt
1000000000.0
1000000000.0
1000000000.000002
1000000000.000002
EOF

# Initial good code
cat << 'EOF' > calc.py
def get_variance(data):
    n = len(data)
    mean = sum(data) / n
    return sum((x - mean) ** 2 for x in data) / (n - 1)
EOF

cat << 'EOF' > stats.py
import calc
with open('/home/user/data.txt', 'r') as f:
    data = [float(x.strip()) for x in f.readlines()]
print(calc.get_variance(data))
EOF

git add calc.py stats.py
git commit -m "Initial commit"

# Create 120 good commits
for i in $(seq 1 120); do
    echo "# Commmit $i" >> stats.py
    git commit -am "chore: update stats $i"
done

# BAD COMMIT
cat << 'EOF' > calc_bad.py
SECRET_TOKEN = "FPT-ANOMALY-RECOVERY-992A"

def get_variance(data):
    n = len(data)
    sum_x = sum(data)
    sum_sq = sum(x**2 for x in data)
    return (sum_sq - (sum_x**2)/n) / (n-1)
EOF

# Compile to pyc and remove source
python3 -m py_compile calc_bad.py
mv __pycache__/calc_bad.*.pyc calc.pyc
rm calc.py calc_bad.py

git rm calc.py
git add calc.pyc
git commit -m "refactor: optimize calc module"
BAD_COMMIT=$(git rev-parse HEAD)

# Next commit restores python file but keeps the bad float logic, minus secret
cat << 'EOF' > calc.py
def get_variance(data):
    n = len(data)
    sum_x = sum(data)
    sum_sq = sum(x**2 for x in data)
    return (sum_sq - (sum_x**2)/n) / (n-1)
EOF

git rm calc.pyc
git add calc.py
git commit -m "fix: restore source code"

# Create remaining commits up to 200
for i in $(seq 124 200); do
    echo "# Commmit $i" >> stats.py
    git commit -am "chore: update stats $i"
done

# Save expected values for verification
cat << EOF > /tmp/expected_state.json
{
  "bad_commit": "$BAD_COMMIT",
  "secret_token": "FPT-ANOMALY-RECOVERY-992A",
  "fixed_variance": 1.3333333333333332e-12
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
