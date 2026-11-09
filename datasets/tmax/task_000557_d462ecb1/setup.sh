#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.jsonl
{"User_Name": "Jos\u00e9", "Email": "jose123@gmail.com", "TIMESTAMP": "1672531200", "Message": "Hello"}
{"user_name": "M\u00fcller", "email": "muller.tech@company.org", "timestamp": "2023-01-02 15:30:00", "message": "Test"}
{"USER_NAME": "\u30c6\u30b9\u30c8", "email": "admin@localhost.local", "timestamp": "1672765200", "message": "System startup"}
{"Name": "Fran\u00e7ois", "eMail": "francois_99@sub.domain.co.uk", "Timestamp": "2023-10-31 08:15:45", "Notes": "None"}
EOF

    chmod -R 777 /home/user
