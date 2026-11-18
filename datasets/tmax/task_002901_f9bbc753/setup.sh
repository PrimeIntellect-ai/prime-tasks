#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest

    mkdir -p /app/incoming /app/docs/by-tag
    touch /app/docs/.lock

    cat << 'EOF' > /app/watcher.conf
PROCESS_SCRIPT=/bin/false
EOF

    cat << 'EOF' > /app/oracle.py
#!/usr/bin/env python3
import sys, re, os

content = sys.stdin.read().strip()
if not content: sys.exit(0)
records = re.split(r'\n\s*\n', content)
for record in records:
    path_match = re.search(r'PATH:\s*(.*)', record)
    author_match = re.search(r'AUTHOR:\s*(.*)', record)
    tags_match = re.search(r'TAGS:\s*(.*)', record)
    if not (path_match and author_match and tags_match): continue

    path = path_match.group(1).strip()
    author = author_match.group(1).strip()
    tags = [t.strip() for t in tags_match.group(1).split(',')]
    filename = os.path.basename(path)
    print(f"[{author}] processed [{filename}] with [{len(tags)}] tags")
EOF
    chmod +x /app/oracle.py

    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 80;
        root /var/www/html;
    }
}
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
