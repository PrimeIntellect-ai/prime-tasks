#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak wget
    pip3 install pytest

    # Create directories
    mkdir -p /app/cjson
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate incident report audio
    espeak -w /app/incident_report.wav "Incident report 8 4 9. The backup node ran out of memory. You must block any aggregation pipeline that groups by the field user_email. I repeat, the restricted field is user_email."

    # Download cJSON
    wget -qO /app/cjson/cJSON.h https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.h
    wget -qO /app/cjson/cJSON.c https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.c

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.json
{"$match": {"status": "active"}}
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.json
[{"$match": {"age": {"$gt": 21}}}, {"$group": {"_id": "$country", "total": {"$sum": 1}}}]
EOF

    cat << 'EOF' > /app/corpus/clean/clean3.json
{"name": "Alice", "role": "admin"}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.json
{"$where": "function() { return this.credits == this.debits; }"}
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.json
[{"$match": {"status": "A"}}, {"$lookup": {"from": "users", "localField": "user_id", "foreignField": "_id", "as": "user"}}]
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.json
[{"$group": {"_id": "$user_email", "count": {"$sum": 1}}}]
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
