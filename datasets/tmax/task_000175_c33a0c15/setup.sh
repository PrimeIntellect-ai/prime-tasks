#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deploy_data.json
[
  {
    "service_name": "auth_mailer",
    "ip_address": "127.0.0.10",
    "port": 2525,
    "email_domain": "auth.corp.com"
  },
  {
    "service_name": "reports_mailer",
    "ip_address": "127.0.0.11"
  },
  {
    "service_name": "billing_mailer",
    "ip_address": "127.0.0.12",
    "port": 2526
  },
  {
    "service_name": "legacy_mailer",
    "port": 2527,
    "email_domain": "legacy.corp.com"
  }
]
EOF

    cat << 'EOF' > /home/user/mail_routing.conf
[core_mailer]
target = 127.0.0.5:2500
domain = core.internal

[auth_mailer]
target = 10.0.0.1:25
domain = oldauth.corp.com
EOF

    chmod -R 777 /home/user
