#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/locales
    mkdir -p /home/user/src
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/locales/ui.json
{
  "btn_submit": "Submit",
  "btn_cancel": "Cancel",
  "lbl_welcome": "Welcome back!"
}
EOF

    cat << 'EOF' > /home/user/locales/errors.json
{
  "err_network": "Network error",
  "err_submit_failed": "Submit",
  "err_auth": "Authentication failed"
}
EOF

    cat << 'EOF' > /home/user/locales/billing.json
{
  "bil_invoice": "Invoice",
  "bil_cancel_sub": "Cancel",
  "bil_submit_payment": "Submit"
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
