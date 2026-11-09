#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest SpeechRecognition pydub sqlglot sqlparse

    mkdir -p /app
    espeak -w /app/dba_notes.wav "We need to stop the database from crashing. Write a validator script with these three rules. Rule one: to prevent deadlocks between concurrent transactions, any transaction that updates both the 'users' table and the 'orders' table must always update 'orders' before 'users'. If a transaction updates 'users' before 'orders', reject it. Rule two: to avoid massive memory spikes, any query utilizing window functions like RANK or ROW_NUMBER must include a PARTITION BY clause. If it lacks a partition, reject it. Rule three: our index strategy requires that any SELECT query hitting the 'transactions' table must include a filter on the 'created_at' column in its WHERE clause. If 'transactions' is queried without filtering on 'created_at', reject it. Anything else should be accepted."

    mkdir -p /home/user/samples
    mkdir -p /app/eval_corpus/evil
    mkdir -p /app/eval_corpus/clean

    cat << 'EOF' > /app/eval_corpus/evil/evil_1.sql
BEGIN; UPDATE users SET status = 1; UPDATE orders SET status = 2; COMMIT;
EOF

    cat << 'EOF' > /app/eval_corpus/evil/evil_2.sql
SELECT id, RANK() OVER (ORDER BY total DESC) FROM sales;
EOF

    cat << 'EOF' > /app/eval_corpus/evil/evil_3.sql
SELECT * FROM transactions WHERE amount > 100;
EOF

    cat << 'EOF' > /app/eval_corpus/clean/clean_1.sql
BEGIN; UPDATE orders SET status = 2; UPDATE users SET status = 1; COMMIT;
EOF

    cat << 'EOF' > /app/eval_corpus/clean/clean_2.sql
SELECT id, RANK() OVER (PARTITION BY region ORDER BY total DESC) FROM sales;
EOF

    cat << 'EOF' > /app/eval_corpus/clean/clean_3.sql
SELECT * FROM transactions WHERE created_at > '2023-01-01' AND amount > 100;
EOF

    cat << 'EOF' > /app/eval_corpus/clean/clean_4.sql
SELECT * FROM unrelated_table;
EOF

    # Create dummy samples
    echo "SELECT * FROM dummy;" > /home/user/samples/sample_1.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
