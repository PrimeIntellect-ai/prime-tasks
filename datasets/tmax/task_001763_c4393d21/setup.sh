#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/site_data/home
    mkdir -p /home/user/site_data/lists
    mkdir -p /home/user/site_data/mail_spool
    touch /home/user/site_data/passwd

    cat << 'EOF' > /home/user/new_hires.csv
FirstName,LastName,Department,Email
Alice,Smith,Engineering,asmith@company.com
Bob,Jones,Sales,bjones@company.com
Alan,Smith,Engineering,alansmith@company.com
Charlie,Smothers,HR,csmothers@company.com
Diana,Smothers,Engineering,dsmothers@company.com
EOF

    cat << 'EOF' > /home/user/access.log
2023-10-01 10:00:00 [bjones] login STATUS=SUCCESS
2023-10-01 10:05:00 [csmother] login STATUS=LOCKED
2023-10-01 10:10:00 [asmith] login STATUS=SUCCESS
2023-10-01 10:15:00 [dsmother] login STATUS=LOCKED
EOF

    chmod -R 777 /home/user
