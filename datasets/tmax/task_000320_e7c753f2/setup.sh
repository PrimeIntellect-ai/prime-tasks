#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gawk
    pip3 install pytest

    mkdir -p /home/user/legacy_pipeline/data /home/user/legacy_pipeline/src /home/user/legacy_pipeline/output /home/user/logs

    cat << 'EOF' > /home/user/legacy_pipeline/data/transactions.csv
TX_001,45.2
TX_002,-12.4
TX_003,78.1
TX_004,-99.9
TX_005,3.3
EOF

    cd /home/user/legacy_pipeline
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init

    cat << 'EOF' > src/math_utils.sh
#!/bin/bash
# Extracts valid numbers for processing
grep -E '^-?[0-9]+\.?[0-9]*$' "$1" > "$2"
EOF
    chmod +x src/math_utils.sh

    cat << 'EOF' > run_pipeline.sh
#!/bin/bash
mkdir -p /home/user/logs
echo "" > /home/user/logs/ingest.log
echo "" > /home/user/logs/process.log
echo "" > /home/user/logs/export.log

awk -F',' '{print $2}' data/transactions.csv > /tmp/values.txt
./src/math_utils.sh /tmp/values.txt /tmp/filtered.txt

awk -F',' '{print "INGEST: " $1 " at " systime()}' data/transactions.csv >> /home/user/logs/ingest.log

# Processing
cat /tmp/filtered.txt | awk '{sum+=$1} END {print "Average: " sum/NR}' > output/stats.txt
EOF
    chmod +x run_pipeline.sh

    git add .
    git commit -m "Initial commit - v1.0"
    git tag v1.0

    # Add dummy commits
    for i in $(seq 1 5); do
      echo "# comment $i" >> src/math_utils.sh
      git commit -am "Dummy commit $i"
    done

    # Introduce the bug (drop the -? in the regex)
    cat << 'EOF' > src/math_utils.sh
#!/bin/bash
# Extracts valid numbers for processing
# comment 1
# comment 2
# comment 3
# comment 4
# comment 5
grep -E '^[0-9]+\.?[0-9]*$' "$1" > "$2"
EOF
    git commit -am "Refactor regex matching for performance"
    BAD_COMMIT=$(git rev-parse HEAD)
    echo $BAD_COMMIT > /tmp/.bad_commit

    # Add more dummy commits
    for i in $(seq 6 10); do
      echo "# comment $i" >> src/math_utils.sh
      git commit -am "Dummy commit $i"
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
