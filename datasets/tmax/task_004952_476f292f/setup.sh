#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/smtpd-stub-0.0.1
    cat << 'EOF' > /app/smtpd-stub-0.0.1/server.py
import sys
print("Starting server with args:", sys.argv)
EOF

    cat << 'EOF' > /app/smtpd-stub-0.0.1/run.sh
#!/bin/bash
PORT=0
python3 server.py --port $PORT
EOF
    chmod +x /app/smtpd-stub-0.0.1/run.sh

    mkdir -p /app/emails/clean
    mkdir -p /app/emails/evil

    cat << 'EOF' > /app/emails/clean/1.eml
Subject: Hello
From: alice@example.com

Hi there!
EOF

    cat << 'EOF' > /app/emails/clean/2.eml
Subject: Meeting notes
From: bob@example.com

Attached are the notes.
EOF

    cat << 'EOF' > /app/emails/clean/3.eml
Subject: Lunch
From: charlie@example.com

Lunch at 12?
EOF

    cat << 'EOF' > /app/emails/evil/1.eml
Subject: Urgent
Subject: Urgent
From: hacker@example.com

Send money.
EOF

    cat << 'EOF' > /app/emails/evil/2.eml
Subject: Normal
From: sneaky@example.com
X-Admin-Bypass: 1

You are hacked.
EOF

    cat << 'EOF' > /app/emails/evil/3.eml
Subject: Double
SUBJECT: Trouble
From: bad@example.com
X-Admin-Bypass: 1

Both conditions met.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
