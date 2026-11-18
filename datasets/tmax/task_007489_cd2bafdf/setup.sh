#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils sed gawk grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
  User ALICE reached out at Alice.Smith+123@domain.com for support.  
Call me at 555-123-4567 regarding the server issue.
  user alice reached out at alice.smith+123@domain.com for support.
Contact billing at (800) 555-9999 or admin@corp.net immediately!


We need more RAM.
we need more ram.  
EOF

    chmod -R 777 /home/user
