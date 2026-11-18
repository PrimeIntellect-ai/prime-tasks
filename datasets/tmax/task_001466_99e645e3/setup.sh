#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick git gawk
    pip3 install pytest

    mkdir -p /app

    # Generate image
    convert -size 800x100 xc:white -fill black -pointsize 24 -annotate +10+50 'FATAL ERROR: db_sync failed. SALT=8392. Halting.' /app/crash_alert.png

    # Setup git repo
    mkdir -p /app/system_repo
    cd /app/system_repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    git branch -m main
    echo "Initial commit" > README.md
    git add README.md
    git commit -m "Init"

    git checkout -b temp_docs
    cat << 'EOF' > validation_rules.txt
Journal Recovery Protocol:
1. Initial database state is always 1000.
2. A journal line is valid ONLY IF: (VALUE * SALT) % 9973 == CHECKSUM
3. For valid lines, apply the ACTION (ADD, SUB, MUL) with the VALUE to the current state.
4. Skip any line where the checksum does not match.
EOF
    git add validation_rules.txt
    git commit -m "Add validation rules"
    git checkout main
    git branch -D temp_docs

    # Setup oracle script
    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
state=1000
salt=8392
while read -r action value checksum; do
    if [ -z "$action" ]; then continue; fi
    expected_checksum=$(( (value * salt) % 9973 ))
    if [ "$checksum" -eq "$expected_checksum" ]; then
        if [ "$action" == "ADD" ]; then
            state=$((state + value))
        elif [ "$action" == "SUB" ]; then
            state=$((state - value))
        elif [ "$action" == "MUL" ]; then
            state=$((state * value))
        fi
    fi
done < "$1"
echo "$state"
EOF
    chmod +x /app/oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
