#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_strings.txt
MSG_01: "Hello, World!"
MSG_02: "hello world"
MSG_03: "Login..."
MSG_04: "Log in!"
MSG_05: "Save Changes?"
MSG_06: "save changes"
MSG_07: "Cancel."
MSG_08: "cancel"
MSG_09: "Error: 404 Not Found"
MSG_10: "error 404 not found"
MSG_11: "Submit."
MSG_12: "Delete User?"
MSG_13: "delete user"
MSG_14: "Profile Settings"
MSG_15: "Loading, please wait..."
MSG_16: "loading please wait"
MSG_17: "Success!"
MSG_18: "success"
MSG_19: "Retry?"
MSG_20: "retry"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
