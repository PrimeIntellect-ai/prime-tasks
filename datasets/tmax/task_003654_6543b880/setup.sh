#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create raw_logs.jsonl
    cat << 'EOF' > /home/user/raw_logs.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "ip": "192.168.1.10", "email": "alice@admin.com", "action": "LOGIN", "status": 200}
{"timestamp": "2023-10-01T10:05:00Z", "ip": "10.0.0.5", "email": "bob@user.com", "action": "VIEW_DASHBOARD", "status": 200}
{"timestamp": "2023-10-01T10:06:00Z", "ip": "192.168.1.10", "email": "alice@admin.com", "action": "LOGIN", "status": 200}
{"timestamp": "2023-10-01T10:10:00Z", "ip": "172.16.0.2", "email": "charlie@guest.com", "action": "DOWNLOAD_FILE", "status": 403}
{"timestamp": "2023-10-01T10:15:00Z", "ip": "10.0.0.5", "email": "bob@user.com", "action": "VIEW_DASHBOARD", "status": 200}
{"timestamp": "2023-10-01T10:20:00Z", "ip": "192.168.1.15", "email": "dave@admin.com", "action": "LOGIN", "status": 200}
{"timestamp": "2023-10-01T10:25:00Z", "ip": "10.0.0.5", "email": "bob@user.com", "action": "UPDATE_PROFILE", "status": 201}
EOF

    # Create report_template.html using base64 to avoid Apptainer build variable syntax errors
    echo "PGh0bWw+Cjxib2R5Pgo8aDE+TG9nIEFuYWx5c2lzIFJlcG9ydDwvaDE+CjxwPlRvdGFsIHJhdyBsb2dzIHByb2Nlc3NlZDoge3tUT1RBTF9SQVd9fTwvcD4KPHA+VG90YWwgdW5pcXVlIGxvZ3MgaWRlbnRpZmllZDoge3tUT1RBTF9VTklRVUV9fTwvcD4KPHA+TW9zdCBmcmVxdWVudCBhY3Rpb246IHt7VE9QX0FDVElPTn19PC9wPgo8L2JvZHk+CjwvaHRtbD4=" | base64 -d > /home/user/report_template.html

    chown -R user:user /home/user
    chmod -R 777 /home/user
