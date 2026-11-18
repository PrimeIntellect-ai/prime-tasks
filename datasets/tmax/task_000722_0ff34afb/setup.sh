#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/log_processor
    cd /home/user/log_processor

    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Initial Good Commit
    cat << 'EOF' > process_logs.sh
#!/bin/bash
grep -o '\] \[[A-Z]*\]' "$1" | awk -F'[][]' '{print $3}' | sort | uniq -c | awk '{print $2": "$1}'
EOF
    chmod +x process_logs.sh
    git add process_logs.sh
    git commit -m "Initial commit"
    git tag v1.0

    # 141 Good Commits
    for i in $(seq 1 141); do
      echo "# Good commit $i" >> process_logs.sh
      git commit -am "Update $i"
    done

    # The Bad Commit (142)
    cat << 'EOF' > process_logs.sh
#!/bin/bash
# Optimized but buggy: matches ANY uppercase word in the line
grep -o '\b[A-Z]\+\b' "$1" | grep -E 'INFO|ERROR|WARN|DEBUG' | sort | uniq -c | awk '{print $2": "$1}'
EOF
    echo "# Bad commit base" >> process_logs.sh
    git commit -am "Optimize log parsing"
    BAD_COMMIT=$(git rev-parse HEAD)
    echo $BAD_COMMIT > /home/user/.expected_bad_commit.txt

    # 58 More Bad Commits
    for i in $(seq 143 200); do
      echo "# Bad commit $i" >> process_logs.sh
      git commit -am "Update $i"
    done

    # Create the test log file
    cat << 'EOF' > /home/user/test_log.txt
[2023-10-01 12:00:00] [INFO] Server started
[2023-10-01 12:01:00] [INFO] User encountered an ERROR
[2023-10-01 12:02:00] [WARN] Disk space low
[2023-10-01 12:03:00] [ERROR] Process crashed
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/log_processor /home/user/test_log.txt /home/user/.expected_bad_commit.txt
    chmod -R 777 /home/user
