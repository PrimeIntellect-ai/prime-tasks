#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/test_corpus/clean
    mkdir -p /app/test_corpus/evil
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create dummy binary
    echo '#!/bin/bash' > /app/query_gen
    echo 'echo "SELECT * FROM edge_list;"' >> /app/query_gen
    chmod +x /app/query_gen

    # Create dummy sql files
    echo "SELECT * FROM edge_list;" > /home/user/corpus/clean/1.sql
    echo "SELECT * FROM edge_list INDEXED BY corrupted_type_idx;" > /home/user/corpus/evil/1.sql
    echo "SELECT * FROM edge_list;" > /app/test_corpus/clean/1.sql
    echo "SELECT * FROM edge_list INDEXED BY corrupted_type_idx;" > /app/test_corpus/evil/1.sql

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
