#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_response.json
{
  "logs": [
    "User admin logged in with CC 1234-5678-9012-3456 at 10:00 AM",
    "Payment processed for CC 9876-5432-1098-7654 successfully",
    "Invalid login attempt by guest"
  ]
}
EOF

    chmod -R 777 /home/user
    chmod 644 /home/user/server_response.json
