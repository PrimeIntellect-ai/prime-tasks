#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc locales
    pip3 install pytest

    # Generate UTF-8 locale
    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8

    # Create data directory
    mkdir -p /home/user/data

    # Create profiles.csv
    cat << 'EOF' > /home/user/data/profiles.csv
UserID,Name,Region
101,Alice,Europe
102,Bob,NorthAmerica
103,Chlöe,Europe
104,Daisuke,Asia
EOF

    # Create chats.txt
    cat << 'EOF' > /home/user/data/chats.txt
LogID|Message
1|Hello [USER:101], please email admin@example.com for help.
2|¡Hola! [USER:103], contact us at support@domain.fr.
3|[USER:104] says こんにちは, my email is test.user%1@tokyo.co.jp!
4|System message for [USER:999]: ping user@test.com
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
