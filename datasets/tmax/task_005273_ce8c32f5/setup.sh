#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_logs.py
import json

logs = [
    # User 1: 4 accesses, granted by admin_007 (Suspicious, highest count)
    {"event_id": "1", "user_id": "u_999", "action": "GRANT", "resource": {"type": "financial_record", "id": "f1"}, "metadata": {"granted_by": "admin_007"}},
    {"event_id": "2", "user_id": "u_999", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f1"}},
    {"event_id": "3", "user_id": "u_999", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f2"}},
    {"event_id": "4", "user_id": "u_999", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f3"}},
    {"event_id": "5", "user_id": "u_999", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f4"}},

    # User 2: 3 accesses, granted by admin_007 (Suspicious)
    {"event_id": "6", "user_id": "u_102", "action": "GRANT", "resource": {"type": "financial_record", "id": "f1"}, "metadata": {"granted_by": "admin_007"}},
    {"event_id": "7", "user_id": "u_102", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f1"}},
    {"event_id": "8", "user_id": "u_102", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f2"}},
    {"event_id": "9", "user_id": "u_102", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f3"}},

    # User 3: 3 accesses, NOT granted by admin_007 (Suspicious, but false flag)
    {"event_id": "10", "user_id": "u_103", "action": "GRANT", "resource": {"type": "financial_record", "id": "f1"}, "metadata": {"granted_by": "admin_002"}},
    {"event_id": "11", "user_id": "u_103", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f1"}},
    {"event_id": "12", "user_id": "u_103", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f2"}},
    {"event_id": "13", "user_id": "u_103", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f3"}},

    # User 4: 2 accesses (Ignored due to threshold)
    {"event_id": "14", "user_id": "u_104", "action": "GRANT", "resource": {"type": "financial_record", "id": "f1"}, "metadata": {"granted_by": "admin_007"}},
    {"event_id": "15", "user_id": "u_104", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f1"}},
    {"event_id": "16", "user_id": "u_104", "action": "ACCESS", "resource": {"type": "financial_record", "id": "f2"}},

    # User 5: 3 accesses, but on medical records (Ignored)
    {"event_id": "17", "user_id": "u_105", "action": "ACCESS", "resource": {"type": "medical_record", "id": "m1"}},
    {"event_id": "18", "user_id": "u_105", "action": "ACCESS", "resource": {"type": "medical_record", "id": "m2"}},
    {"event_id": "19", "user_id": "u_105", "action": "ACCESS", "resource": {"type": "medical_record", "id": "m3"}}
]

with open('/home/user/audit_logs.jsonl', 'w') as f:
    for log in logs:
        f.write(json.dumps(log) + '\n')
EOF

    python3 /home/user/setup_logs.py
    rm /home/user/setup_logs.py

    chmod -R 777 /home/user
