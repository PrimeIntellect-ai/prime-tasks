#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/mock_libs
    touch /home/user/mock_libs/libalpha.so
    touch /home/user/mock_libs/libbeta.so
    touch /home/user/mock_libs/libdelta.so
    touch /home/user/mock_libs/libepsilon.so

    cat << 'EOF' > /home/user/deps.txt
AppCore: bGliYWxwaGEuc28gQU5EIGxpYmJldGEuc28=
AppUI: bGliZ2FtbWEuc28gT1IgbGliZGVsdGEuc28=
AppNet: bGliYWxwaGEuc28gQU5EIGxpYm9tZWdhLnNv
AppData: bGlib21lZ2Euc28gT1IgbGlic2lnbWEuc28=
AppUtil: bGliZXBzaWxvbi5zbw==
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
