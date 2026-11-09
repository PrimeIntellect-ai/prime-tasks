#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/events.csv
timestamp,user_id,event_type,payload
2023-10-01T10:00:00Z,U101,click,"{""browser"": ""Chrome"", ""duration"": 45, ""meta"": ""bad \u12G unicode""}"
2023-10-01T10:05:00Z,U102,view,"{""browser"": ""Firefox"", ""duration"": 120, ""meta"": ""ok""}"
2023-10-01T10:10:00Z,U101,click,"{""browser"": ""Chrome"", ""meta"": ""missing duration""}"
2023-10-01T10:15:00Z,U102,view,"{""browser"": ""Safari"", ""duration"": 300, ""meta"": ""bad \u00H""}"
2023-10-01T10:20:00Z,U103,click,"{""browser"": ""Edge"", ""duration"": 400, ""meta"": ""ok""}"
2023-10-01T10:25:00Z,U102,click,"{""browser"": ""Firefox"", ""meta"": ""missing duration \u99Z""}"
EOF

    chmod -R 777 /home/user
