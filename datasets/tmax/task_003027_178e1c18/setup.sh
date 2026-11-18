#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ git cron wget imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app
    convert -size 600x200 xc:white -font Liberation-Sans -pointsize 18 -fill black -annotate +10+30 "METRICS DASHBOARD CONFIGURATION\n===============================\nService Port: 7331\nRequired Bearer Token: T0k3n_S3cr3t\nMetrics File: /home/user/metrics_output.json" /app/dashboard_config.png

    useradd -m -s /bin/bash user || true

    wget https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h -O /home/user/httplib.h

    mkdir -p /home/user/source_repo
    cd /home/user/source_repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    touch file1 && git add file1 && git commit -m "commit 1"
    touch file2 && git add file2 && git commit -m "commit 2"
    touch file3 && git add file3 && git commit -m "commit 3"
    cd /

    cat << 'EOF' > /home/user/cron_task.sh
#!/bin/sh
cd source_repo
count=$(git rev-list --count HEAD)
echo "{\"commits\": $count}" > metrics_output.json
EOF
    chmod +x /home/user/cron_task.sh

    chmod -R 777 /home/user
    chmod -R 777 /app
