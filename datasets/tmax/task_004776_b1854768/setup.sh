#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git tesseract-ocr imagemagick gawk
    pip3 install pytest

    mkdir -p /app

    # Create the customer screenshot
    convert -size 1000x200 xc:white -font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf -pointsize 16 -fill black -draw "text 10,50 'FATAL ERROR: Data corruption detected during parallel aggregation. Last stable execution before commit a1b2c3d4e5f678901234567890abcdef12345678.'" /app/customer_screenshot.png || \
    convert -size 1000x200 xc:white -pointsize 16 -fill black -draw "text 10,50 'FATAL ERROR: Data corruption detected during parallel aggregation. Last stable execution before commit a1b2c3d4e5f678901234567890abcdef12345678.'" /app/customer_screenshot.png

    # Create reference oracle
    cat << 'EOF' > /app/reference_process_logs.sh
#!/bin/bash
awk '{counts[$1]++} END {for (user in counts) print user, counts[user]}' | sort
EOF
    chmod +x /app/reference_process_logs.sh

    # Create repository
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/log_pipeline_repo
    cd /home/user/log_pipeline_repo
    git init
    git config user.name "Admin"
    git config user.email "admin@example.com"

    # Initial stable commit
    cat << 'EOF' > process_logs.sh
#!/bin/bash
awk '{counts[$1]++} END {for (user in counts) print user, counts[user]}' | sort
EOF
    chmod +x process_logs.sh
    git add process_logs.sh
    git commit -m "Initial stable version"

    # Buggy commit
    cat << 'EOF' > process_logs.sh
#!/bin/bash
# Process logs in parallel (buggy)
tmpfile="/tmp/counts_$$.txt"
rm -f "$tmpfile"
touch "$tmpfile"
while read line; do
    user=$(echo "$line" | awk '{print $1}')
    count=$(grep "^$user " "$tmpfile" 2>/dev/null | awk '{print $2}')
    if [ -z "$count" ]; then count=0; fi
    count=$((count+1))
    grep -v "^$user " "$tmpfile" > "${tmpfile}.tmp" 2>/dev/null || true
    echo "$user $count" >> "${tmpfile}.tmp"
    mv "${tmpfile}.tmp" "$tmpfile"
done
cat "$tmpfile" | sort
rm -f "$tmpfile" "${tmpfile}.tmp"
EOF
    git add process_logs.sh
    git commit -m "Optimize processing"

    # Create a tag so the hash resolves
    git tag a1b2c3d4e5f678901234567890abcdef12345678

    chown -R user:user /home/user
    chmod -R 777 /home/user
