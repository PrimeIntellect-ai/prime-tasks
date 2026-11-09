#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/legacy_db.csv
admin,8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918
guest,84983c60f7daadc1cb8698621f802c0d9f9a3c3c295c810748fb048115c186ec
service,e2a3fdb71c6999a4bb3c5d8a9e7f86445098ffb9a674d8c7ea329580a8b9e6c4
unknown,definitelynothere1234567890abcdef1234567890abcdef
EOF

    cat << 'EOF' > /home/user/wordlist.txt
123456
password
admin
guest
letmein123
qwerty
root
EOF

    echo -n "supersecretkey1234567890abcdef" > /home/user/master.key

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
