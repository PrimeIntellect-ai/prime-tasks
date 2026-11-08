#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/db_engine
    mkdir -p /home/user/data

    # Setup git repository
    cd /home/user/db_engine
    git init -b main
    git config user.name "SRE"
    git config user.email "sre@example.com"

    # Initial commit and tag v1.0
    cat << 'EOF' > db_read.sh
#!/bin/bash
# Valid WAL processing rules documented here:
# The WAL file contains base64 encoded lines.
# When decoded, valid lines follow the format: [PASSWORD] KEY=VALUE
echo "Reading DB"
EOF
    chmod +x db_read.sh
    git add db_read.sh
    git commit -m "Initial commit"
    git tag v1.0

    # Commits 1 to 130
    for i in $(seq 1 130); do
        echo "Dummy commit $i" > dummy.txt
        git add dummy.txt
        git commit -m "Refactor part $i"
    done

    # Commit 131: Introduce bug
    cat << 'EOF' > db_read.sh
#!/bin/bash
# Valid WAL processing rules documented here:
# The WAL file contains base64 encoded lines.
# When decoded, valid lines follow the format: [PASSWORD] KEY=VALUE
echo "Reading DB"
exit 1
EOF
    git add db_read.sh
    git commit -m "Optimize WAL processing"

    # Commit 132: Hardcode recovery password
    echo "RECOVERY_PASS=X9T2mPqL_992" > config.sh
    git add config.sh
    git commit -m "Add config for recovery"

    # Commit 133: Remove recovery password
    echo "# Config file" > config.sh
    git add config.sh
    git commit -m "Remove hardcoded secret"

    # Commits 134 to 200
    for i in $(seq 134 200); do
        echo "Dummy commit $i" > dummy.txt
        git add dummy.txt
        git commit -m "Refactor part $i"
    done

    # Setup data
    cd /home/user/data
    echo "ADMIN_USER=admin_old" > prod.db
    echo "X9T2mPqL_992 ADMIN_USER=super_admin_99" | base64 > prod.db.wal
    echo "invalid_data_without_password" | base64 >> prod.db.wal

    # Create user and permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
