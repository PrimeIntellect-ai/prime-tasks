#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar git
    pip3 install pytest click click-default-group tabulate python-dateutil sqlite-fts4

    # Download and extract sqlite-utils 3.35
    mkdir -p /app
    cd /app
    wget https://github.com/simonw/sqlite-utils/archive/refs/tags/3.35.tar.gz
    tar -xzf 3.35.tar.gz
    rm 3.35.tar.gz

    # Inject the bug: hardcode UNIQUE in create_index
    sed -i 's/CREATE {unique}INDEX/CREATE UNIQUE INDEX/g' /app/sqlite-utils-3.35/sqlite_utils/db.py

    # Create directories
    mkdir -p /home/user/data/clean
    mkdir -p /home/user/data/evil

    # Create valid CSV
    cat << 'EOF' > /home/user/data/clean/valid_1.csv
employee_id,parent_id,name
1,,Alice
2,1,Bob
3,1,Charlie
4,2,Dave
EOF

    # Create cycle CSV
    cat << 'EOF' > /home/user/data/evil/cycle_1.csv
employee_id,parent_id,name
1,3,Alice
2,1,Bob
3,2,Charlie
EOF

    # Create bad schema CSV
    cat << 'EOF' > /home/user/data/evil/bad_schema.csv
emp_id,name,department
1,Alice,HR
2,Bob,IT
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
