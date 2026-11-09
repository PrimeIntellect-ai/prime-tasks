#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > wordlist.txt
password123
admin123
supersecret99
qwerty
winter2023
letmein1
EOF

    cat << 'EOF' > shadow.bak
admin:24a3dbbc5bfdb0cc06757bbdfab9f7336ed13ee863f69b56f93bf14ebbd68f7b
EOF

    cat << 'EOF' > web_server.log
[INFO] GET /index.html 200
[INFO] GET /images/logo.png 200
[WARN] GET /download?file=../../../../home/user/shadow.bak 200
[INFO] POST /upload?file=payload.enc 201
[INFO] GET /contact 200
EOF

    cat << 'EOF' > payload.enc
a3w0ano0azs6ejo=
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
