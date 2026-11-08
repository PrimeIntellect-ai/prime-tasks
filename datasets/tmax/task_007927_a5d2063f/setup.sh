#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git sqlite3 sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    mkdir -p /home/user/monitor_app
    cd /home/user/monitor_app

    # 1. Git Repo Setup
    mkdir -p config_repo
    cd config_repo
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init
    echo '{"endpoint": "https://api.ping.local", "API_KEY": "super_secret_uptime_key_992"}' > config.json
    git add config.json
    git commit -m "Initial commit with config"
    echo '{"endpoint": "https://api.ping.local"}' > config.json
    git add config.json
    git commit -m "Remove sensitive API key"
    cd ..

    # 2. Build Script Setup
    cat << 'EOF' > build.sh
#!/bin/bash
echo "Starting build process..."
# Syntax error: missing quote
echo "Checking dependencies...
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed."
    exit 1
fi
echo "Build complete." > /home/user/monitor_app/build_success.log
EOF
    chmod +x build.sh

    # 3. Corrupted Logs and Ingest Script
    cat << 'EOF' > uptime_logs.txt
1690000000 200
1690000005 500
corrupted_line_garbage
1690000010 200
1690000015 timeout
1690000020 200
EOF

    cat << 'EOF' > ingest.sh
#!/bin/bash
DB="/home/user/monitor_app/uptime.db"
sqlite3 $DB "CREATE TABLE IF NOT EXISTS pings (ts INTEGER, status INTEGER);"

while read -r ts status; do
    # This will fail on corrupted lines when sqlite tries to process garbage
    sqlite3 $DB "INSERT INTO pings (ts, status) VALUES ($ts, $status);"
done < /home/user/monitor_app/uptime_logs.txt

# Bad query
sqlite3 $DB "SELECT SUM(status) FROM pings WHERE status = 'SUCCESS';"
EOF
    chmod +x ingest.sh

    # 4. Race Condition Setup
    echo "0" > alert_state.txt
    cat << 'EOF' > alert.sh
#!/bin/bash
FILE="/home/user/monitor_app/alert_state.txt"
# Buggy increment without lock
val=$(cat $FILE)
sleep 0.05
new_val=$((val + 1))
echo $new_val > $FILE
EOF
    chmod +x alert.sh

    cat << 'EOF' > run_alerts_test.sh
#!/bin/bash
echo "0" > /home/user/monitor_app/alert_state.txt
for i in {1..50}; do
    /home/user/monitor_app/alert.sh &
done
wait
EOF
    chmod +x run_alerts_test.sh

    chown -R user:user /home/user/monitor_app
    chmod -R 777 /home/user
