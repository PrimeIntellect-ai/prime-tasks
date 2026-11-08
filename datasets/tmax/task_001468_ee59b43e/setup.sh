#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /app/audio
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /app/etl

    # Generate audio memo using espeak and ffmpeg
    echo "Hey, the ETL is failing for three reasons. First, the NoSQL endpoints are getting DOSed. I need you to write sanitizer.py to reject any MongoDB aggregation pipeline that uses the '\$where' operator, or uses a '\$lookup' stage where the 'foreignField' is anything other than 'account_id', because 'account_id' is our only indexed field. Everything else should be accepted. Second, bad_query.sql is doing an implicit cross join between users and transactions. Look at schema.sql, join them properly on user_id, and then use a ROW_NUMBER window function to only return the single most recent transaction per user based on transaction_date descending. Finally, our referral logic is broken. Read referrals.json and write graph_path.py to find the shortest path between any two users." > /tmp/memo.txt
    espeak -f /tmp/memo.txt -w /app/audio/architect_memo.wav

    # Create schema.sql
    cat << 'EOF' > /app/etl/schema.sql
CREATE TABLE users (
    user_id UUID PRIMARY KEY,
    name VARCHAR(255)
);
CREATE TABLE transactions (
    tx_id UUID PRIMARY KEY,
    user_id UUID,
    amount DECIMAL,
    transaction_date TIMESTAMP
);
EOF

    # Create bad_query.sql
    cat << 'EOF' > /app/etl/bad_query.sql
SELECT u.name, t.amount, t.transaction_date 
FROM users u, transactions t;
EOF

    # Create referrals.json
    cat << 'EOF' > /app/etl/referrals.json
{
  "A": ["B", "C"],
  "B": ["D"],
  "C": ["E", "F"],
  "D": ["G"],
  "E": ["G"],
  "F": [],
  "G": []
}
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/valid1.json
[{"$match": {"status": "A"}}, {"$lookup": {"from": "docs", "localField": "acc", "foreignField": "account_id", "as": "res"}}]
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/bad_lookup.json
[{"$lookup": {"from": "users", "localField": "email", "foreignField": "email", "as": "u"}}]
EOF

    cat << 'EOF' > /app/corpus/evil/bad_where.json
[{"$match": {"$where": "this.balance > 1000"}}]
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
