#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    mkdir -p /home/user/legacy_project/logs/old
    mkdir -p /home/user/legacy_project/assets

    cat << 'EOF' > /home/user/legacy_project/logs/app.log
User admin@example.com logged in.
Error connecting to db.
Contact support@domain.co.uk for help.
EOF

    cat << 'EOF' > /home/user/legacy_project/logs/old/debug.log
test1@test.com
no email here
test.user@sub.domain.org triggered an event.
EOF

    python3 -c "
with open('/home/user/legacy_project/assets/file1_bin', 'wb') as f:
    f.write(b'\x7f\x45\x4c\x46\x02\x01\x01\x00')
with open('/home/user/legacy_project/assets/file2_img', 'wb') as f:
    f.write(b'\x89\x50\x4e\x47\x0d\x0a\x1a\x0a')
with open('/home/user/legacy_project/assets/file3_rand', 'wb') as f:
    f.write(b'\x00\x00\x00\x00\x00\x00\x00\x00')
with open('/home/user/legacy_project/assets/file4_bin', 'wb') as f:
    f.write(b'\x7f\x45\x4c\x46\x01\x01\x01\x00')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
