#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create logs
    mkdir -p /home/user/ticket_data
    cat << 'EOF' > /home/user/ticket_data/producer.log
[10:00:01] Sent MSG_001 expected_sequence=1
[10:00:02] Sent MSG_002 expected_sequence=2
[10:00:03] Sent MSG_003 expected_sequence=3
[10:00:04] Sent MSG_004 expected_sequence=4
[10:00:05] Sent MSG_005 expected_sequence=5
EOF

    cat << 'EOF' > /home/user/ticket_data/consumer.log
[10:00:01] Processed MSG_001 actual_sequence=1
[10:00:02] Processed MSG_002 actual_sequence=2
[10:00:03] Processed MSG_003 actual_sequence=3
[10:00:04] Processed MSG_004 actual_sequence=3
[10:00:05] Processed MSG_005 actual_sequence=5
EOF

    # Setup Git Repository
    mkdir -p /home/user/message_processor
    cd /home/user/message_processor
    git init
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git checkout -b main

    # Initial commit (v1.0) - Good
    cat << 'EOF' > processor.py
import asyncio

shared_counter = 0

async def process_messages():
    global shared_counter
    shared_counter += 1
    return shared_counter
EOF
    git add processor.py
    git commit -m "Initial commit"
    git tag v1.0

    # Commits 1-3 - Good
    echo "# Comment 1" >> processor.py
    git commit -am "Commit 1"
    echo "# Comment 2" >> processor.py
    git commit -am "Commit 2"
    echo "# Comment 3" >> processor.py
    git commit -am "Commit 3"

    # Commit 4 - Bad
    cat << 'EOF' > processor.py
import asyncio

shared_counter = 0

async def process_messages():
    global shared_counter
    temp = shared_counter
    await asyncio.sleep(0.001)
    shared_counter = temp + 1
    return shared_counter

# Comment 1
# Comment 2
# Comment 3
EOF
    git commit -am "Commit 4 - Introduce race condition"

    # Commits 5-7 - Bad
    echo "# Comment 4" >> processor.py
    git commit -am "Commit 5"
    echo "# Comment 5" >> processor.py
    git commit -am "Commit 6"
    echo "# Comment 6" >> processor.py
    git commit -am "Commit 7"

    chmod -R 777 /home/user
