#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev tzdata
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/mail/inbox

    # Create initial files
    cat << 'EOF' > /home/user/mail/inbox/msg1.eml
Sender: alice
Date: 2023-11-15T14:30:00Z
Subject: System update
EOF

    cat << 'EOF' > /home/user/mail/inbox/msg2.eml
Sender: charlie
Date: 2023-11-15T18:45:00Z
Subject: Hello
EOF

    cat << 'EOF' > /home/user/mail/inbox/msg3.eml
Sender: david
Date: 2023-11-16T01:15:00Z
Subject: Question
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
