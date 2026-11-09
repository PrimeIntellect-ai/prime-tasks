#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang imagemagick fonts-dejavu-core coreutils
    pip3 install pytest

    mkdir -p /app /home/user/log_manager /home/user/active_logs

    # Generate dummy log data
    for i in 1 2 3 4 5; do
        yes "INFO: system is running normally at timestamp 2023-10-10 with no errors observed." | head -n 20000 > /home/user/active_logs/app_${i}.log
    done

    # Create skeleton main.go
    cat << 'EOF' > /home/user/log_manager/main.go
package main

import "fmt"

func main() {
    fmt.Println("Skeleton")
}
EOF

    # Generate runbook image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 14 -fill black -draw "text 10,20 'DEPLOYMENT RUNBOOK v2.1\n-----------------------\nEnsure the following variables are strictly used:\nCRON_SCHEDULE: \"*/15 * * * *\"\nENV_PATH: \"/usr/local/go/bin:/usr/bin:/bin:/home/user/log_manager/bin\"\nBACKUP_DIR: \"/home/user/archived_logs\"'" /app/runbook_spec.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
