#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo curl build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/logs.json
[
  {
    "id": "log1",
    "url": "/login?redirect=https://evil.com/login",
    "headers": {
      "Authorization": "Basic dXNlcjpwYXNzd29yZA==" 
    }
  },
  {
    "id": "log2",
    "url": "/login?redirect=http%3A%2F%2Fexample.com%2F%3Fq%3D%3Cscript%3Ealert(1)%3C%2Fscript%3E",
    "headers": {
      "Authorization": "Basic dXNlcjpwYXNzOnJvbGU9YWRtaW4="
    }
  },
  {
    "id": "log3",
    "url": "/login",
    "headers": {
      "Authorization": "Basic dGVzdDp0ZXN0"
    }
  },
  {
    "id": "log4",
    "url": "/login?redirect=javascript%3Aalert%28document.cookie%29",
    "headers": {
      "Authorization": "Basic YWRtaW46YWRtaW46cm9sZT1hZG1pbg=="
    }
  },
  {
    "id": "log5",
    "url": "/login?redirect=https://example.com.evil.net/auth",
    "headers": {
      "Authorization": "Basic dXNlcjpwYXNz"
    }
  }
]
EOF

    chmod -R 777 /home/user
