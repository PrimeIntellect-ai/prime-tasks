#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/system/configs/app1
    mkdir -p /home/user/system/configs/app2/nested
    mkdir -p /home/user/system/configs/legacy

    # Use python to generate exact file contents
    python3 -c "
import os

with open('/home/user/system/configs/app1/server.conf', 'wb') as f:
    f.write(b'A'*50 + b'B'*50 + b'C'*20)

with open('/home/user/system/configs/app2/nested/db.conf', 'wb') as f:
    f.write(b'secretdata')

with open('/home/user/system/configs/legacy/old.conf', 'wb') as f:
    f.write(b'1234567890'*6)

with open('/home/user/system/configs/app1/ignore.conf', 'wb') as f:
    f.write(b'old config')

with open('/home/user/system/configs/app1/empty.conf', 'wb') as f:
    pass
"

    # Create baseline stamp
    touch -d "2023-01-01 12:00:00" /home/user/system/baseline.stamp

    # Set timestamps
    touch -d "2023-01-02 12:00:00" /home/user/system/configs/app1/server.conf
    touch -d "2023-01-02 12:00:00" /home/user/system/configs/app2/nested/db.conf
    touch -d "2023-01-02 12:00:00" /home/user/system/configs/legacy/old.conf
    touch -d "2022-12-31 12:00:00" /home/user/system/configs/app1/ignore.conf
    touch -d "2023-01-02 12:00:00" /home/user/system/configs/app1/empty.conf

    # Create overrides file
    cat << 'EOF' > /home/user/system/overrides.txt
/home/user/system/configs/app2/nested/db.conf
/home/user/system/configs/nonexistent.conf

EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/system
    chmod -R 777 /home/user
