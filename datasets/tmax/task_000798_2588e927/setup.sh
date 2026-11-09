#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip espeak
    pip3 install pytest pyinstaller

    mkdir -p /app /verifier

    # Generate audio file
    espeak -w /app/audit_interview.wav "I set the evidence password to start with the word securebox followed by a three digit pin."

    # Create access.log
    cat << 'EOF' > /app/access.log
10.0.5.12 - - [10/Oct/2023:13:55:36 -0700] "GET /login?next=http://evil.com/ HTTP/1.1" 302 123
192.168.1.105 - - [10/Oct/2023:14:00:12 -0700] "GET /login?next=https://evil.com/login HTTP/1.1" 302 123
203.0.113.42 - - [10/Oct/2023:14:15:00 -0700] "GET /login?next=//evil.com/ HTTP/1.1" 302 123
127.0.0.1 - - [10/Oct/2023:14:20:00 -0700] "GET /login?next=/dashboard HTTP/1.1" 302 123
EOF

    # Create oracle script
    cat << 'EOF' > /tmp/oracle.py
import sys
from urllib.parse import urlparse, urlencode, parse_qsl, urlunparse

def sanitize(url):
    if url.startswith("//") or url.startswith("\\\\") or url.startswith("http://") or url.startswith("https://"):
        return "/login"
    try:
        parsed = urlparse(url)
    except Exception:
        return "/login"
    query = parse_qsl(parsed.query, keep_blank_values=True)
    query = [q for q in query if q[0] != 'token']
    parsed = parsed._replace(query=urlencode(query))
    return urlunparse(parsed)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(sanitize(sys.argv[1]))
    else:
        print("/login")
EOF

    # Compile oracle
    cd /tmp
    pyinstaller --onefile oracle.py
    cp dist/oracle /app/oracle_redirect
    cp dist/oracle /verifier/oracle_redirect
    chmod +x /verifier/oracle_redirect

    # Zip evidence
    cd /app
    zip -P securebox842 evidence.zip access.log oracle_redirect
    rm access.log oracle_redirect

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
