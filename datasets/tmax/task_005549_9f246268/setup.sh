#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/auth.log
2023-10-01 10:00:00 user1 LOGIN
2023-10-01 10:05:00 user1 LOGOUT
2023-10-01 10:01:00 user2 LOGIN
2023-10-01 10:06:00 user2 LOGOUT
EOF

    cat << 'EOF' > /home/user/logs/data.log
2023-10-01 10:02:00 user1 UPLOAD 150
2023-10-01 10:03:00 user2 UPLOAD 50
2023-10-01 10:04:00 user1 DOWNLOAD 20
EOF

    cat << 'EOF' > /home/user/billing_processor.py
import threading
import json
import glob
import os
from datetime import datetime

all_events = []
revenue = 0.0

def parse_logs(filepath):
    global all_events
    local_events = []
    with open(filepath, 'r') as f:
        for line in f:
            parts = line.strip().split(' ', 3)
            if len(parts) >= 3:
                ts_str = parts[0] + ' ' + parts[1]
                ts = datetime.strptime(ts_str, '%Y-%m-%d %H:%M:%S')
                local_events.append((ts, parts[2], parts[3] if len(parts)>3 else ''))

    # Bug 1: Unsafe append to global list if not GIL protected, or just appending without sorting context
    # actually list.extend is thread-safe in CPython but let's assume they overwrite or +=
    global all_events
    all_events = all_events + local_events

def process_billing():
    global revenue
    users = {}
    active_sessions = set()

    # Bug 2: Events are not sorted! 
    # all_events.sort(key=lambda x: x[0])  <-- MISSING

    for event in all_events:
        ts, user, action_data = event
        action = action_data.split(' ')[0]
        val = int(action_data.split(' ')[1]) if len(action_data.split(' ')) > 1 else 0

        if user not in users:
            users[user] = 0.0

        if action == 'LOGIN':
            active_sessions.add(user)
            users[user] += 1.50
        elif action == 'LOGOUT':
            if user in active_sessions:
                active_sessions.remove(user)
        else:
            if user not in active_sessions:
                users[user] += 10.00 # Penalty for unauthorized action
                continue

            if action == 'UPLOAD':
                # Bug 3: Incorrect tiered formula
                if val <= 100:
                    cost = val * 0.05
                else:
                    cost = (100 * 0.05) + (val * 0.02) # Should be (val - 100) * 0.02
                users[user] += cost
            elif action == 'DOWNLOAD':
                users[user] += val * 0.10

    # Bug 1b: Race condition simulated in calculation if we had multiple threads, 
    # but here revenue is just sum. Let's make revenue calculation a dummy race condition or just rely on total.
    for u, cost in users.items():
        # A real race condition would be if threads updated this, but keeping it simple:
        revenue += cost

    with open('/home/user/final_billing.json', 'w') as f:
        json.dump({"total_revenue": revenue, "users": users}, f, indent=2)

if __name__ == "__main__":
    threads = []
    for f in glob.glob('/home/user/logs/*.log'):
        t = threading.Thread(target=parse_logs, args=(f,))
        threads.append(t)
        t.start()
    for t in threads:
        t.join()

    process_billing()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
