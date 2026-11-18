#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate instructions.wav
    espeak -w /app/instructions.wav "Attention analyst. We have a breach. You must block all tickets originating from the employee hierarchy starting at manager ID 8492. Furthermore, block any tickets where the payload contains the NoSQL injection operators dollar where or dollar regex. End of message."

    # Create employees.csv
    cat << 'EOF' > /app/employees.csv
emp_id,name,manager_id,department
8492,Root Evil,,Sales
1001,Sub Evil 1,8492,Sales
1002,Sub Evil 2,8492,Sales
2001,Minion 1,1001,Sales
2002,Minion 2,1001,Sales
2003,Minion 3,1002,Sales
9000,Good Guy,,IT
9001,Good Sub 1,9000,IT
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/ticket_001.json
{
    "author_id": 9000,
    "query_payload": {
        "$eq": "test_value"
    }
}
EOF

    cat << 'EOF' > /app/corpus/clean/ticket_002.json
{
    "author_id": 9001,
    "query_payload": {
        "$in": ["a", "b"]
    }
}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/ticket_003.json
{
    "author_id": 2001,
    "query_payload": {
        "$eq": "test_value"
    }
}
EOF

    cat << 'EOF' > /app/corpus/evil/ticket_004.json
{
    "author_id": 9000,
    "query_payload": {
        "$where": "this.value > 0"
    }
}
EOF

    cat << 'EOF' > /app/corpus/evil/ticket_005.json
{
    "author_id": 9001,
    "query_payload": {
        "$regex": ".*"
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
