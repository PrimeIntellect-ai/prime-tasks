#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq curl
    pip3 install pytest

    mkdir -p /home/user/app/data
    mkdir -p /home/user/app/tests

    cat << 'EOF' > /home/user/app/data/access.jsonl
{"path": "/home", "status": 200, "user_agent": "Mozilla/5.0"}
{"path": "/api/login", "status": 200, "user_agent": "curl/7.68.0"}
{"path": "/about", "status": 200, "user_agent": "Mozilla/5.0"}
{"path": "/home", "status": 200, "user_agent": "Chrome/90.0"}
{"path": "/api/data", "status": 500, "user_agent": "Mozilla/5.0"}
{"path": "/api/login", "status": 401, "user_agent": "PostmanRuntime/7.26.8"}
{"path": "/home", "status": 200, "user_agent": "Safari/605.1.15"}
{"path": "/about", "status": 200, "user_agent": "Chrome/90.0"}
{"path": "/contact", "status": 404, "user_agent": "bot"}
{"path": "/api/login", "status": 200, "user_agent": "curl/7.68.0"}
EOF

    cat << 'EOF' > /home/user/app/legacy_processor.py
import helper
import sys

def process(url):
    data = helper.fetch(url)
    # Aggregation logic...
    pass

if __name__ == "__main__":
    process(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/app/helper.py
import legacy_processor

def fetch(url):
    pass
EOF

    cat << 'EOF' > /home/user/app/tests/expected.txt
3 /home
2 /about
2 /api/login
EOF

    cat << 'EOF' > /home/user/app/tests/format_update.patch
--- expected.txt	2023-10-01 12:00:00.000000000 +0000
+++ expected.txt	2023-10-01 12:01:00.000000000 +0000
@@ -1,3 +1,3 @@
-3 /home
-2 /about
-2 /api/login
+/home,3
+/about,2
+/api/login,2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
