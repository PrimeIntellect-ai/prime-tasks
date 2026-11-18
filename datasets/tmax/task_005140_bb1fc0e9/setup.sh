#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming

    cat << 'EOF' > /home/user/incoming/A.dat
1672531500,DEV01,15
1672532000,DEV01,20
1672532000,DEV03,50
EOF

    cat << 'EOF' > /home/user/incoming/B.dat
1672539000,DEV01,18
1672539000,DEV02,99
1672546000,DEV01,25
EOF

    cat << 'EOF' > /home/user/incoming/C.dat
1672531500,DEV01,15
1672532000,DEV01,20
1672532000,DEV03,50
EOF

    cat << 'EOF' > /home/user/incoming/D.dat
1672546500,DEV01,22
1672546800,DEV04,11
EOF

    chmod -R 777 /home/user
