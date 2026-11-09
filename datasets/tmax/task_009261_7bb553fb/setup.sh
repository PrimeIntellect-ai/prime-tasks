#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/locks

    cat << 'EOF' > /home/user/services.conf
# Core Services Configuration
web=enabled
db=enabled  # Database service requires special parsing
cache=disabled
api=enabled # API gateway
EOF

    cat << 'EOF' > /home/user/deploy_system.sh
#!/bin/bash

LOCK_DIR="/home/user/locks"
mkdir -p "$LOCK_DIR"
rm -f "$LOCK_DIR"/*.lock

TOTAL_SERVICES=0
ENABLED_SERVICES=0

# Read config and process
while IFS='=' read -r name status; do
    # Skip pure comments or empty lines
    if [[ "$name" == \#* ]] || [[ -z "$name" ]]; then
        continue
    fi

    TOTAL_SERVICES=$((TOTAL_SERVICES + 1))

    # BUG: Does not strip trailing whitespace or inline comments from $status
    if [ "$status" = "enabled" ]; then
        ENABLED_SERVICES=$((ENABLED_SERVICES + 1))
        touch "$LOCK_DIR/$name.lock"
    fi
done < "/home/user/services.conf"

EXPECTED_ENABLED=3

assert_convergence() {
    local actual=$(ls -1 "$LOCK_DIR"/*.lock 2>/dev/null | wc -l || echo 0)
    if [ "$actual" -ne "$EXPECTED_ENABLED" ]; then
        echo "Build Failure: Convergence not reached. Expected $EXPECTED_ENABLED locks, found $actual." >&2
        exit 1
    fi
}

assert_convergence
echo "Deployment converged successfully."
EOF

    chmod +x /home/user/deploy_system.sh

    chmod -R 777 /home/user
