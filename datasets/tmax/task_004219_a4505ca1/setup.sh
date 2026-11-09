#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/investigation/system_dump/etc/
    mkdir -p /home/user/investigation/system_dump/opt/maintenance/

    echo "root    ALL=(ALL:ALL) ALL" > /home/user/investigation/system_dump/etc/sudoers
    echo "%admin  ALL=(ALL) ALL" >> /home/user/investigation/system_dump/etc/sudoers
    echo "www-data ALL=(root) NOPASSWD: /home/user/investigation/system_dump/opt/maintenance/cleanup.sh" >> /home/user/investigation/system_dump/etc/sudoers

    cat << 'EOF' > /home/user/investigation/system_dump/opt/maintenance/cleanup.sh
#!/bin/bash
rm -rf /tmp/cache/*
EOF
    chmod +x /home/user/investigation/system_dump/opt/maintenance/cleanup.sh

    cat << 'EOF' > /home/user/investigation/http_logs.json
[
  {
    "timestamp": "2023-10-01T10:00:00Z",
    "source_ip": "192.168.1.50",
    "method": "GET",
    "path": "/index.html",
    "headers": {
      "User-Agent": "Mozilla/5.0",
      "Accept": "*/*"
    },
    "cookies": {
      "session_id": "ab1234567890"
    }
  },
  {
    "timestamp": "2023-10-01T10:05:12Z",
    "source_ip": "203.0.113.88",
    "method": "GET",
    "path": "/images/logo.png",
    "headers": {
      "User-Agent": "curl/7.68.0",
      "X-Debug-Data": "user_123_data_123-45-6789_end"
    },
    "cookies": {
      "session_id": "invalid"
    }
  },
  {
    "timestamp": "2023-10-01T10:08:33Z",
    "source_ip": "203.0.113.88",
    "method": "POST",
    "path": "/api/health",
    "headers": {
      "User-Agent": "curl/7.68.0",
      "Accept": "application/json"
    },
    "cookies": {
      "tracker": "987-65-4321"
    }
  }
]
EOF

    chmod -R 777 /home/user
