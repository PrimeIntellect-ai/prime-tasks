#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc shc jq tar coreutils
    pip3 install pytest

    # Create the legacy backup_packer binary
    mkdir -p /app
    cat << 'EOF' > /tmp/packer.sh
#!/bin/bash

PAYLOAD=$(cat)
PREFIX=$(echo "$PAYLOAD" | jq -r '.prefix')

TMPDIR=$(mktemp -d)
cd "$TMPDIR"
mkdir -p "$PREFIX"

echo "$PAYLOAD" | jq -c '.items[]' | while read -r item; do
    PATH_VAL=$(echo "$item" | jq -r '.path')
    CONTENT=$(echo "$item" | jq -r '.content')
    MODE=$(echo "$item" | jq -r '.mode')

    FULL_PATH="$PREFIX/$PATH_VAL"
    mkdir -p "$(dirname "$FULL_PATH")"
    echo "$CONTENT" | base64 -d > "$FULL_PATH"
    chmod "$MODE" "$FULL_PATH"
done

tar -cf - \
    --sort=name \
    --format=gnu \
    --mtime="2024-01-01 00:00:00Z" \
    --owner=0 --group=0 --numeric-owner \
    "$PREFIX" | base64

cd /
rm -rf "$TMPDIR"
EOF

    chmod +x /tmp/packer.sh
    shc -f /tmp/packer.sh -o /app/backup_packer
    rm -f /tmp/packer.sh /tmp/packer.sh.x.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
