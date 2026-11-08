#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/resolve_deps.sh
#!/bin/bash
# /home/user/resolve_deps.sh
# Usage: ./resolve_deps.sh <target_item> <db_file>

TARGET="$1"
DB_FILE="$2"

if [[ -z "$TARGET" || -z "$DB_FILE" ]]; then
    echo "Usage: $0 <target> <db_file>"
    exit 1
fi

resolve() {
    local target="$1"

    # Read dependencies for the target
    local deps=$(grep "^${target}:" "$DB_FILE" | cut -d':' -f2)

    if [[ -z "$deps" ]]; then
        echo "Resolved leaf: $target"
        return
    fi

    echo "Resolving $target..."
    for d in $(echo "$deps" | tr ',' ' '); do
        resolve "$d"
    done
}

resolve "$TARGET"
EOF

    chmod +x /home/user/resolve_deps.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
