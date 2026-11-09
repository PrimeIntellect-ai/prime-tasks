#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/log_processor
    cd /home/user

    # Create the log file
    cat << 'EOF' > generate_logs.sh
#!/bin/bash
for i in {1..20000}; do
    if (( i % 15 == 0 )); then
        echo "[$i] ERROR: Connection timed out"
    elif (( i % 7 == 0 )); then
        echo "[$i] WARNING: High memory usage"
    else
        echo "[$i] INFO: Processing request successfully"
    fi
done
EOF
    bash generate_logs.sh > /home/user/large_logs.txt
    rm generate_logs.sh

    cd /home/user/log_processor
    git init
    git config user.name "Perf Engineer"
    git config user.email "perf@example.com"

    # Commit 1: v1.0 (Fast)
    cat << 'EOF' > process_logs.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <logfile>"
    exit 1
fi
grep -E "ERROR|WARNING" "$1"
EOF
    chmod +x process_logs.sh
    git add process_logs.sh
    git commit -m "Initial release of log processor"
    git tag v1.0

    # Commit 2: Add comments
    cat << 'EOF' > process_logs.sh
#!/bin/bash
# Log processing script
# Extracts errors and warnings
if [ -z "$1" ]; then
    echo "Usage: $0 <logfile>"
    exit 1
fi
grep -E "ERROR|WARNING" "$1"
EOF
    git add process_logs.sh
    git commit -m "Add comments to script"

    # Commit 3: The Regression (Slow loop instead of grep)
    cat << 'EOF' > process_logs.sh
#!/bin/bash
# Log processing script
# Extracts errors and warnings
if [ -z "$1" ]; then
    echo "Usage: $0 <logfile>"
    exit 1
fi

# Updated logic for future extensibility
while IFS= read -r line; do
    if echo "$line" | grep -qE "ERROR|WARNING"; then
        echo "$line"
    fi
done < "$1"
EOF
    git add process_logs.sh
    git commit -m "Refactor processing loop for extensibility"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Commit 4: Add trailing newline feature/fix
    cat << 'EOF' > process_logs.sh
#!/bin/bash
# Log processing script
# Extracts errors and warnings
if [ -z "$1" ]; then
    echo "Usage: $0 <logfile>"
    exit 1
fi

# Updated logic for future extensibility
while IFS= read -r line; do
    if echo "$line" | grep -qE "ERROR|WARNING"; then
        echo "$line"
    fi
done < "$1"
echo "" # Ensure trailing newline
EOF
    git add process_logs.sh
    git commit -m "Ensure trailing newline in output"

    # Save the bad commit hash
    echo "$BAD_COMMIT" > /tmp/.bad_commit_hash

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
