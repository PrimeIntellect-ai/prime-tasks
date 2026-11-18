#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/chat_logs.txt
[2023-10-01 10:05:12] U001: Hello, my email is alice.smith@example.com and my phone is 555-123-4567.
[2023-10-01 10:06:00] U002: I need help with my account.
[2023-10-01 10:07:30] U001: Can you also update my secondary email to alice2@work.net?
[2023-10-01 10:08:15] U003: Call me at 999-888-7777 ASAP!
[2023-10-01 10:10:05] U002: Thanks, that fixed it.
[2023-10-01 10:12:00] U001: Great, thanks.
[2023-10-01 10:15:22] U003: Also my wife's number is 111-222-3333 and her email is wife@home.org.
EOF

    chmod -R 777 /home/user
