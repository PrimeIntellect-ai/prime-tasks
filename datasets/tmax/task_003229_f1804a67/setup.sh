#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data

    # Create users.csv (UTF-8)
    cat << 'EOF' > /home/user/data/users.csv
uuid,username,department
a1b2c3d4-0000-0000-0000-000000000001,alice,Engineering
a1b2c3d4-0000-0000-0000-000000000002,bob,Sales
a1b2c3d4-0000-0000-0000-000000000003,charlie,Marketing
a1b2c3d4-0000-0000-0000-000000000004,diana,Engineering
EOF

    # Create activity.log (UTF-16LE)
    cat << 'EOF' > /tmp/activity.utf8.log
[INFO] 2023-10-25 10:00:00 System started
[INFO] 2023-10-25 10:05:00 User<a1b2c3d4-0000-0000-0000-000000000001> logged in
[DEBUG] 2023-10-25 10:06:00 User<a1b2c3d4-0000-0000-0000-000000000001> viewed dashboard
[WARN] 2023-10-25 10:07:00 User<a1b2c3d4-0000-0000-0000-000000000003> failed login
[INFO] 2023-10-25 10:08:00 User<a1b2c3d4-0000-0000-0000-000000000004> uploaded file
[INFO] 2023-10-25 10:09:00 User<a1b2c3d4-0000-0000-0000-000000000001> logged out
[INFO] 2023-10-25 10:10:00 User<UNKNOWN-UUID> did something
[ERROR] 2023-10-25 10:11:00 System crashed
EOF

    iconv -f UTF-8 -t UTF-16LE /tmp/activity.utf8.log > /home/user/data/activity.log
    rm /tmp/activity.utf8.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
