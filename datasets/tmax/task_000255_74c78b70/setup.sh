#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_chat.log
25-Oct-2023 14:15:00 -0700 | U001 | Contact me at alice.smith@email.com
25-Oct-2023 14:45:00 -0700 | U002 | Call 555-123-4567.
25-Oct-2023 15:05:00 -0700 | U001 | Wait, try 999-888-7777 instead.
25-Oct-2023 15:59:59 -0700 | U003 | My email is bob_jones@domain.org!
25-Oct-2023 16:00:00 -0700 | U004 | No PII here.
25-Oct-2023 16:30:00 -0700 | U004 | Just following up on ticket 1234.
25-Oct-2023 23:10:00 +0000 | U005 | Different timezone test: foo.bar@test.co.uk
EOF

    chmod -R 777 /home/user
