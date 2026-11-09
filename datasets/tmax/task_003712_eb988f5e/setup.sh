#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/locales.jsonl
{"id":"btn_ok","en":"OK","fr":"D'accord"}
{"id":"btn_cancel","en":"Cancel\u202","fr":""}
{"id":"lbl_name","en":"User Name"}
{"id":"msg_welcome","en":"Welcome back\u002!","fr":"Bon retour!"}
{"id":"msg_error","en":"Error \u26A","fr":""}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
