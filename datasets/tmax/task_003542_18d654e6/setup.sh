#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/v1
    mkdir -p /home/user/workspace
    mkdir -p /home/user/mail_queue/incoming
    ln -s /home/user/app/v1 /home/user/app/current

    echo '#!/bin/bash' > /home/user/app/v1/dispatcher
    echo 'echo "v1 running"' >> /home/user/app/v1/dispatcher
    chmod +x /home/user/app/v1/dispatcher

    cat << 'EOF' > /home/user/mail_queue/incoming/msg1.eml
From: admin@localhost
To: announce@localhost
Date: Mon, 1 Jan 2024 10:00:00 +0000
Message-ID: abc-123-xyz

This is an announcement.
EOF

    cat << 'EOF' > /home/user/mail_queue/incoming/msg2.eml
From: user1@localhost
To: discuss@localhost
Date: Mon, 1 Jan 2024 10:05:00 +0000
Message-ID: def-456-uvw

Let's discuss this.
EOF

    cat << 'EOF' > /home/user/mail_queue/incoming/msg3.eml
From: user2@localhost
To: discuss@localhost
Date: Mon, 1 Jan 2024 10:10:00 +0000
Message-ID: 789-ghi

Reply to discussion.
EOF

    chmod -R 777 /home/user
