#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create necessary directories
    mkdir -p /app/sql-graph-proj-1.0.0/sql_graph_proj
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create the broken vendored package
    cat << 'EOF' > /app/sql-graph-proj-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name='sql-graph-proj',
    version='1.0.0',
    packages=find_packages(),
    install_requires=['sqlite3>=4.0'],
)
EOF

    touch /app/sql-graph-proj-1.0.0/sql_graph_proj/__init__.py

    cat << 'EOF' > /app/sql-graph-proj-1.0.0/sql_graph_proj/compiler.py
def build_query():
    join_str = " CROSS JOIN "
    return f"SELECT * FROM table1{join_str}table2"
EOF

    # Create the clean corpus
    cat << 'EOF' > /app/corpus/clean/1.sql
SELECT * FROM authors INNER JOIN papers ON authors.id = papers.author_id;
EOF

    cat << 'EOF' > /app/corpus/clean/2.sql
SELECT a.name FROM a JOIN b ON a.id = b.id WHERE a.age > 20;
EOF

    # Create the evil corpus
    cat << 'EOF' > /app/corpus/evil/1.sql
SELECT * FROM authors, papers;
EOF

    cat << 'EOF' > /app/corpus/evil/2.sql
SELECT * FROM a CROSS JOIN b;
EOF

    # Ensure permissions for /app
    chmod -R 777 /app

    # Create user and set home permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
