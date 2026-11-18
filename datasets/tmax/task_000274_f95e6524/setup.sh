#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl redis-server nodejs npm
    pip3 install pytest

    mkdir -p /home/user/workspace
    mkdir -p /app/corpus

    cat << 'EOF' > /home/user/workspace/legacy_filter.py
import sys, urllib.parse
raw = sys.stdin.read().strip()
decoded = urllib.parse.unquote_plus(raw)
if '<' in decoded or '>' in decoded or '../' in decoded or '\x00' in decoded:
    print("REJECTED")
    sys.exit(1)
print(f"ACCEPTED: {decoded}")
sys.exit(0)
EOF

    cat << 'EOF' > /home/user/workspace/config.env
FILTER_BIN=/home/user/workspace/legacy_filter.py
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
EOF

    echo "hello+world" > /app/corpus/clean.txt
    echo "test%20data" >> /app/corpus/clean.txt

    echo "%3Cscript%3E" > /app/corpus/evil.txt
    echo "..%2F..%2Fetc%2Fpasswd" >> /app/corpus/evil.txt
    echo "null%00byte" >> /app/corpus/evil.txt

    echo "#!/bin/bash\necho 'Services started'" > /home/user/workspace/start_services.sh
    echo "#!/bin/bash\necho 'Running tests'" > /home/user/workspace/run_corpus_tests.sh
    echo "#!/bin/bash\necho 'Report generated' > /home/user/workspace/test_report.log" > /home/user/workspace/generate_report.sh

    chmod +x /home/user/workspace/*.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
