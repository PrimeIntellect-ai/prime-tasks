#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/activity_wide.csv
Timestamp,AppAlpha,AppBeta,AppGamma
2023-10-01T10:00:00Z,Login-Success_US,ERR_500-Timeout,
2023-10-01T10:15:00Z,,Login:Success_EU,Sync-Complete
2023-10-01T10:45:00Z,ERR:404_Not_Found,,Data_Load_100%
2023-10-01T11:00:00Z,Login-Success_US,ERR_500-Timeout,Sync-Complete
2023-10-01T11:30:00Z,,,
2023-10-01T11:45:00Z,Logout_User_123,Logout_User_456,Data_Load_100%
EOF

    chmod -R 777 /home/user
