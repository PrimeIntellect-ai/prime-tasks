#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak g++ curl wget
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    espeak -w /app/meeting.wav "Please update the query firewall. The restricted user IDs are 404, 808, and 909. Ensure these are not accessed."

    cat << 'EOF' > /app/corpus/clean/clean1.json
[{"$match": {"user_id": 100}}, {"$graphLookup": {"from": "users", "startWith": 100, "connectFromField": "friends", "connectToField": "_id", "as": "network"}}]
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.json
[{"$setWindowFields": {"partitionBy": "$department", "sortBy": {"date": 1}, "output": {"cum_sales": {"$sum": "$sales", "window": {"documents": ["unbounded", "current"]}}}}}]
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.json
[{"$match": {"user_id": 404}}]
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.json
[{"$graphLookup": {"from": "users", "startWith": 808, "connectFromField": "friends", "connectToField": "_id", "as": "network"}}]
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.json
[{"$setWindowFields": {"sortBy": {"date": 1}, "output": {"cum_sales": {"$sum": "$sales"}}}}]
EOF

    cat << 'EOF' > /app/corpus/evil/evil4.json
[{"$match": {"user_id": {"$in": [100, 200, 909]}}}]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
