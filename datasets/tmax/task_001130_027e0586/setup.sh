#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    espeak -w /app/requirements.wav "Here are the rules for our ETL pipeline validator. First, any query that references both the 'employees' and 'departments' tables must have a proper join condition on 'department_id'. If it joins them with a comma or an explicit CROSS JOIN without matching 'department_id', it is an evil implicit cross join. Second, any query that selects from the 'logs' table must have a LIMIT clause, and that limit must not exceed 1000. If it lacks a limit or the limit is over 1000, it's evil. Everything else is clean."

    cat << 'EOF' > /app/corpus/clean/clean1.sql
SELECT * FROM employees JOIN departments ON employees.department_id = departments.department_id;
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.sql
SELECT * FROM logs LIMIT 500;
EOF

    cat << 'EOF' > /app/corpus/clean/clean3.sql
SELECT * FROM other_table;
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.sql
SELECT * FROM employees, departments;
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.sql
SELECT * FROM logs LIMIT 2000;
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.sql
SELECT * FROM logs;
EOF

    cat << 'EOF' > /app/corpus/evil/evil4.sql
SELECT * FROM employees CROSS JOIN departments;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
