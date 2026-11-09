#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    cd /home/user/app

    git config --global init.defaultBranch main
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"

    git init

    # Commit 1: Initial safe version
    cat << 'EOF' > monitor.sh
#!/bin/bash
while true; do
    sleep 0.1
    # Process simulated items
    item=$(date +%s)
    current_item="$item"
done
EOF
    chmod +x monitor.sh
    git add monitor.sh
    git commit -m "Initial commit of monitor daemon"

    # Commit 2: Accidentally hardcoded secret
    cat << 'EOF' > config.sh
API_KEY="AKIA-TREASURE-778899"
EOF
    git add config.sh
    git commit -m "Add config file"

    # Commit 3: Remove secret and require env var
    cat << 'EOF' > config.sh
# API_KEY should be passed as an environment variable
EOF
    cat << 'EOF' > monitor.sh
#!/bin/bash
if [ -z "$API_KEY" ]; then
    echo "Error: API_KEY environment variable is required."
    exit 1
fi

while true; do
    sleep 0.1
    # Process simulated items
    item=$(date +%s)
    current_item="$item"
done
EOF
    git add config.sh monitor.sh
    git commit -m "Secure API key handling"

    # Commit 4: Add logging feature (Safe)
    cat << 'EOF' > monitor.sh
#!/bin/bash
if [ -z "$API_KEY" ]; then
    echo "Error: API_KEY environment variable is required."
    exit 1
fi

echo "Starting monitor..."
while true; do
    sleep 0.1
    item=$(date +%s)
    current_item="$item"
done
EOF
    git add monitor.sh
    git commit -m "Add startup logging"

    # Commit 5: Introduce the memory leak (Bad)
    cat << 'EOF' > monitor.sh
#!/bin/bash
if [ -z "$API_KEY" ]; then
    echo "Error: API_KEY environment variable is required."
    exit 1
fi

echo "Starting monitor..."
PROCESSED_ITEMS=()
while true; do
    sleep 0.1
    item=$(date +%s)
    PROCESSED_ITEMS+=("$item") # Memory leak here
    current_item="$item"
done
EOF
    git add monitor.sh
    git commit -m "Track processed items"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Commit 6: Formatting fixes (Bad)
    cat << 'EOF' > monitor.sh
#!/bin/bash
if [ -z "$API_KEY" ]; then
    echo "Error: API_KEY environment variable is required."
    exit 1
fi

echo "Starting monitor daemon..."
PROCESSED_ITEMS=()

while true; do
    sleep 0.1
    item=$(date +%s)
    PROCESSED_ITEMS+=("$item")
    current_item="$item"
done
EOF
    git add monitor.sh
    git commit -m "Format monitor.sh"

    # Store the bad commit for verification purposes
    echo "$BAD_COMMIT" > /home/user/.secret_bad_commit

    chown -R user:user /home/user/app /home/user/.secret_bad_commit
    chmod -R 777 /home/user
