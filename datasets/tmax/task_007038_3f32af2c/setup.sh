#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo
    cd /home/user/repo
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Commit 1 (Good)
    cat << 'EOF' > service.sh
#!/bin/bash
while true; do
    new_event=$(date)
    sleep 1
done
EOF
    chmod +x service.sh
    git add service.sh
    git commit -m "Initial commit"

    # Commit 2
    echo "PORT=8080" > config.sh
    git add config.sh
    git commit -m "Add config"

    # Commit 3 (Secret added)
    echo "PORT=8080" > config.sh
    echo "API_TOKEN=AKIA_SECRET_987654321" >> config.sh
    git add config.sh
    git commit -m "Update config with token"

    # Commit 4 (Secret removed)
    echo "PORT=8080" > config.sh
    git add config.sh
    git commit -m "Remove sensitive data"

    # Commit 5 (Bad commit - Memory leak)
    cat << 'EOF' > service.sh
#!/bin/bash
history_log=()
while true; do
    new_event=$(date)
    history_log+=("$new_event")
    sleep 1
done
EOF
    git add service.sh
    git commit -m "Add event logging"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Commit 6
    echo "# End of script" >> service.sh
    git add service.sh
    git commit -m "Add comment"

    # Save expected truth values
    echo "$BAD_COMMIT" > /tmp/expected_commit
    echo "AKIA_SECRET_987654321" > /tmp/expected_token

    chmod -R 777 /home/user
