#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    # Create directories
    mkdir -p /app/bash-log-archiver-1.0
    mkdir -p /data/logs
    mkdir -p /data/archive

    # Create archive.sh
    cat << 'EOF' > /app/bash-log-archiver-1.0/archive.sh
#!/bin/bash
file=$1
dest=$2

if [ -z "$file" ] || [ -z "$dest" ]; then
    echo "Usage: $0 <file> <dest_dir>"
    exit 1
fi

filename=$(basename "$file")
tmp_file=$(mktemp)

while IFS= read -r line; do
    if [[ "$line" != *"[DEBUG]"* ]]; then
        echo "$line" >> "$tmp_file"
    fi
done < "$file"

mv "$tmp_file" "$dest/${filename%.log}.archive"
EOF
    chmod +x /app/bash-log-archiver-1.0/archive.sh

    # Create Makefile with the DEST_DIR typo
    cat << 'EOF' > /app/bash-log-archiver-1.0/Makefile
DEST_DIR ?= /data/archive
run:
	mkdir -p $(DEST_DIR)
	find /data/logs -name "*.log" -mtime +7 -exec /app/bash-log-archiver-1.0/archive.sh {} $(DEST_DIR) \;
EOF

    # Create dummy logs
    for i in {1..5}; do
        echo "[INFO] Old Log $i" > /data/logs/old_$i.log
        echo "[DEBUG] Debug info $i" >> /data/logs/old_$i.log
        touch -d "10 days ago" /data/logs/old_$i.log
    done

    for i in {1..3}; do
        echo "[INFO] New Log $i" > /data/logs/new_$i.log
        echo "[DEBUG] Debug info $i" >> /data/logs/new_$i.log
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /data
