#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 git
pip3 install pytest

mkdir -p /home/user/metrics_pipeline
cd /home/user/metrics_pipeline
git init
git config user.email "test@example.com"
git config user.name "Test User"

# Commit 1 (v1.0) - Good
cat << 'EOF' > process_metrics.sh
#!/bin/bash

INPUT=$1
DB=$(mktemp -d)/db.sqlite
sqlite3 "$DB" "CREATE TABLE metrics (id INTEGER, status TEXT, value INTEGER);"
sqlite3 "$DB" ".mode csv" ".import '$INPUT' metrics"

# Calculate average value for active items
RESULT=$(sqlite3 "$DB" "SELECT IFNULL(SUM(value)/COUNT(value), 0) FROM metrics WHERE status='active';")

# Assertion
if [ -z "$RESULT" ]; then
    echo "Assertion failed: Result is empty!" >&2
    exit 1
fi
echo "Average: $RESULT"
EOF
chmod +x process_metrics.sh
git add process_metrics.sh
git commit -m "Initial working script"
git tag v1.0

# Commit 2 - Harmless change
echo "# Comment added" >> process_metrics.sh
git commit -am "Add comment"

# Commit 3 - The Bad Commit (Regression)
cat << 'EOF' > process_metrics.sh
#!/bin/bash

INPUT=$1
DB=$(mktemp -d)/db.sqlite
sqlite3 "$DB" "CREATE TABLE metrics (id INTEGER, status TEXT, value INTEGER);"
sqlite3 "$DB" ".mode csv" ".import '$INPUT' metrics"

# Calculate average value for active items (ignore 0 values in denominator)
RESULT=$(sqlite3 "$DB" "SELECT SUM(value)/COUNT(NULLIF(value, 0)) FROM metrics WHERE status='active';")

# Assertion
if [ -z "$RESULT" ]; then
    echo "Assertion failed: Result is empty!" >&2
    exit 1
fi
echo "Average: $RESULT"
EOF
chmod +x process_metrics.sh
git commit -am "Update average logic to ignore zero values"
BAD_COMMIT=$(git rev-parse HEAD)

# Commit 4 - Another harmless change
echo "# End of script" >> process_metrics.sh
git commit -am "Add end comment"

# Save the bad commit to a hidden place for verification
echo $BAD_COMMIT > /tmp/.truth_bad_commit

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
