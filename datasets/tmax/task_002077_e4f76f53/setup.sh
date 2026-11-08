#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/logs/server1.log
2023-11-05 500
2023-11-08 200
2023-11-12 300
EOF

    cat << 'EOF' > /home/user/logs/server2.log
2023-11-07 400
2023-11-09 250
EOF

    mkdir -p /home/user/uptime-monitor
    cd /home/user/uptime-monitor
    git init
    git config user.name "Admin"
    git config user.email "admin@example.com"

    cat << 'EOF' > config.txt
API_KEY="SRE_PROD_99382A"
EOF
    git add config.txt
    git commit -m "Initial commit with config"

    rm config.txt
    git rm config.txt
    git commit -m "Remove sensitive config file"

    cat << 'EOF' > monitor.sh
#!/bin/bash
if [ "$API_KEY" != "SRE_PROD_99382A" ]; then
    echo "Invalid API KEY"
    exit 1
fi

score=0
for log in "$@"; do
    while read -r date uptime_ms; do
        # Extract day and calculate weighted score
        day=$(echo "$date" | cut -d'-' -f3)
        # Bug: 08 and 09 evaluate as invalid octal numbers in bash arithmetic
        weighted=$((day * uptime_ms))
        score=$((score + weighted))
    done < "$log"
done
echo "$score"
EOF
    chmod +x monitor.sh
    git add monitor.sh
    git commit -m "Add monitor script"

    chmod -R 777 /home/user
