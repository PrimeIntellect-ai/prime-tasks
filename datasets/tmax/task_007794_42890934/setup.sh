#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/events.log
user_a,VIEW_ITEM
user_b,LOGIN
user_c,LOGIN
user_b,VIEW_ITEM
user_a,LOGIN
user_c,VIEW_ITEM
user_b,ADD_CART
user_d,LOGIN
user_d,VIEW_ITEM
user_d,LOGOUT
user_d,ADD_CART
user_b,CHECKOUT
user_c,LOGOUT
user_c,LOGIN
user_c,VIEW_ITEM
user_c,ADD_CART
user_c,CHECKOUT
user_a,VIEW_ITEM
user_a,ADD_CART
user_e,LOGIN
user_e,VIEW_ITEM
user_e,ADD_CART
user_e,VIEW_ITEM
user_e,CHECKOUT
EOF

    chmod -R 777 /home/user
