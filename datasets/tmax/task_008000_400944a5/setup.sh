#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_changes.txt
Ticket: CHG001
Date: 2023-10-01T10:00:00Z
IP: 10.0.5.22
Password: superSecretPassword!
Notes: Initial deployment of the
web server configuration.
---
Ticket: CHG002
IP: 172.16.254.1
Notes: Restarted service.
No password changes.
---
Ticket: CHG003
Date: 2023-10-02T14:30:00Z
IP: 192.168.100.5
Password: hunter2
Notes: Upgraded database
schema.
Applied migrations.
---
Ticket: CHG004
IP: 8.8.4.4
Notes: DNS update only.
EOF

    cat << 'EOF' > /home/user/.expected_processed_changes.jsonl
{"ticket_id": "CHG001", "notes": "Initial deployment of the web server configuration.", "timestamp": "2023-10-01T10:00:00Z", "target_ip": "X.X.5.22", "password": "[REDACTED]"}
{"ticket_id": "CHG002", "notes": "Restarted service. No password changes.", "timestamp": "2023-10-01T10:00:00Z", "target_ip": "X.X.254.1"}
{"ticket_id": "CHG003", "notes": "Upgraded database schema. Applied migrations.", "timestamp": "2023-10-02T14:30:00Z", "target_ip": "X.X.100.5", "password": "[REDACTED]"}
{"ticket_id": "CHG004", "notes": "DNS update only.", "timestamp": "2023-10-02T14:30:00Z", "target_ip": "X.X.4.4"}
EOF

    cat << 'EOF' > /home/user/.expected_pipeline.log
Total records processed: 4
Records with imputed dates: 2
Records with masked passwords: 2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
