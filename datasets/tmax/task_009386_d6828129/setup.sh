#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/build_data.b64
QW5hbHl0aWNzTW9kdWxlLDEuOS4wLHByb2R1Y3Rpb24=
QW5hbHl0aWNzTW9kdWxlLDEuMTAuMSxwcm9kdWN0aW9u
QW5hbHl0aWNzTW9kdWxlLDIuMC4wLWJldGEscHJvZHVjdGlvbg==
QW5hbHl0aWNzTW9kdWxlLDIuMC4wLHN0YWdpbmc=
UGF5bWVudEFwcCwxLjIuMTQscHJvZHVjdGlvbg==
UGF5bWVudEFwcCwxLjUuMCxzdGFnaW5n
UGF5bWVudEFwcCwxLjMuMixwcm9kdWN0aW9u
Q2hhdEFwcCwwLjkuOSxwcm9kdWN0aW9u
Q2hhdEFwcCwxLjAuMC1yYzEscHJvZHVjdGlvbg==
Q2hhdEFwcCwxLjAuMCxwcm9kdWN0aW9u
QXV0aExpYiwzLjAuMCxzdGFnaW5n
EOF

    chown user:user /home/user/build_data.b64
    chmod 644 /home/user/build_data.b64

    chmod -R 777 /home/user
