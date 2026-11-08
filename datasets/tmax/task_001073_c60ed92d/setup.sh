#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the audio file
    espeak -w /app/intercepted_dev_meeting.wav "Alright team, for the new endpoint, the JSON payload has target_file and body. The sanitiser needs to be strict. For target_file, it must only allow files ending in exactly '.txt' or '.log'. Absolutely no directory traversal allowed, so block anything containing '../'. Also block any absolute paths starting with '/etc' or '/var'. For the body field, we need to prevent XSS. Block any payload that contains the substring '<script' or 'javascript:'. Finally, reject the payload if 'onload=' or 'onerror=' is present in the body. If any of these are found, dump the request."

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.json
{"target_file": "report.txt", "body": "This is a normal log entry."}
EOF
    cat << 'EOF' > /app/corpus/clean/clean2.json
{"target_file": "folder/access.log", "body": "User logged in safely. No weird html here."}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.json
{"target_file": "../report.txt", "body": "Normal body."}
EOF
    cat << 'EOF' > /app/corpus/evil/evil2.json
{"target_file": "/etc/passwd.txt", "body": "Normal"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil3.json
{"target_file": "report.pdf", "body": "Normal"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil4.json
{"target_file": "report.log", "body": "Here is a <script>alert(1)</script>"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil5.json
{"target_file": "report.log", "body": "Click here javascript:alert(1)"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil6.json
{"target_file": "test.txt", "body": "<img src=x onerror=alert(1)>"}
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
