#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git socat netcat-openbsd gawk
    pip3 install pytest

    mkdir -p /app/repo
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create dummy logs
    cat << 'EOF' > /app/dummy_logs.txt
2023-10-12 10:00:00 [INFO] Metric=50
2023-10-12 10:00:01 [WARN] Metric=100
2023-10-12 10:00:02 [ERROR] Metric=0
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/logs.txt
2023-10-12 10:00:00 [INFO] Metric=0
2023-10-12 10:00:01 [WARN] Metric=100
2023-10-12 10:00:02 [ERROR] Metric=50
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/logs.txt
2023-10-12 10:00:00 [INFO] Metric=-1
2023-10-12 10:00:01 [INFO] Metric=101
2023-10-12 10:00:01 [DEBUG] Metric=50
2023-10-12 10:00:00 [INFO] Metric=abc
2023-10-12 10:00:00 INFO Metric=50
EOF

    # Setup git repo
    cd /app/repo
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Working script
    cat << 'EOF' > filter.sh
#!/bin/bash
while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ \[(INFO|WARN|ERROR)\]\ Metric=([0-9]+)$ ]]; then
        metric="${BASH_REMATCH[2]}"
        if (( metric >= 0 && metric <= 100 )); then
            echo "$line"
        fi
    fi
done
EOF
    chmod +x filter.sh
    git add filter.sh
    git commit -m "Initial working filter"

    # Broken script
    cat << 'EOF' > filter.sh
#!/bin/bash
while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ \[(INFO|WARN|ERROR)\]\ Metric=([0-9]+)$ ]]; then
        metric="${BASH_REMATCH[2]}"
        if (( metric > 0 && metric < 100 )); then
            echo "$line"
        fi
    fi
done
EOF
    git add filter.sh
    git commit -m "Refactor metric boundaries"

    # Start services script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
socat TCP4-LISTEN:8001,fork,reuseaddr EXEC:"cat /app/dummy_logs.txt" &
socat TCP4-LISTEN:8002,fork,reuseaddr EXEC:"tee -a /tmp/pipeline_out.log" &
echo "Services started."
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
