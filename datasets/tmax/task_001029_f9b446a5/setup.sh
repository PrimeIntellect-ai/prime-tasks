#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_events.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "user_id": 101, "event": "login", "notes": "System normal"}
{"timestamp": "2023-10-01T10:00:05Z", "user_id": 102, "event": "purchase", "notes": "Broken escape \uZZZZ here"}
{"timestamp": "2023-10-01T10:00:12Z", "user_id": 103, "event": "logout", "notes": "Another bad one \u12X3"}
{"timestamp": "2023-10-01T10:00:15Z", "user_id": 105, "event": "view_item", "notes": "Normal"}
EOF

    cat << 'EOF' > /home/user/users.csv
user_id,region,tier
101,NA,Pro
102,EU,Free
103,AP,Pro
104,NA,Free
105,SA,Free
EOF

    # Initialize an empty crontab or dummy entry to ensure 'crontab -l' works without error if appended
    echo "# Initial crontab" | crontab -u user -
    # Also for root just in case the tests run as root
    echo "# Initial crontab" | crontab -

    chmod -R 777 /home/user
