#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq sqlite3 gawk sed coreutils
    pip3 install pytest

    mkdir -p /home/user/app/migrations

    cat << 'EOF' > /home/user/app/config.ini
[Global]
debug=true

[Database]
host=127.0.0.1
port=5432
user=ci_tester
password=secret

[API]
endpoint=https://api.example.com
EOF

    cat << 'EOF' > /home/user/app/migrations/001_init.sql
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
EOF

    cat << 'EOF' > /home/user/app/migrations/002_add_status.sql
ALTER TABLE users ADD COLUMN status TEXT;
EOF

    cat << 'EOF' > /home/user/app/migrations/003_seed.sql
INSERT INTO users (name, status) VALUES ('admin', 'active');
EOF

    cat << 'EOF' > /home/user/app/processor.sh
#!/bin/bash
# Dummy processor script
sleep 3
echo "Processing complete."
EOF
    chmod +x /home/user/app/processor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
