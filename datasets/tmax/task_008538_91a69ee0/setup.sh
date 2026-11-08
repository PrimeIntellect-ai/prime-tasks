#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/bin

    # Create v1.db
    cat << 'EOF' > /home/user/v1.db
1,alice,admin
2,bob,user
3,charlie,moderator
EOF

    # Create e2e_tester
    cat << 'EOF' > /home/user/bin/e2e_tester
#!/bin/bash
if [ -z "$MAX_CORES" ] || [ "$MAX_CORES" -ge 4 ]; then
    echo "Constraint violation: MAX_CORES invalid"
    exit 1
fi

if ! [ -f "$1" ]; then
    echo "Missing database file"
    exit 1
fi

# Check for correct v2 format in one of the lines
if grep -q "^2,user,bob,true$" "$1"; then
    echo "Test suite passed: verified 3 entities."
    exit 0
else
    echo "Test suite failed: schema validation error."
    exit 1
fi
EOF
    chmod +x /home/user/bin/e2e_tester

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
