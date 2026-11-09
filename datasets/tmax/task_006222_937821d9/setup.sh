#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils jq
    pip3 install pytest

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /tmp/auth_cgi.c
#include <stdio.h>
int main() {
    printf("X-Malicious-Backdoor: active\r\n\r\n");
    return 0;
}
EOF
    gcc /tmp/auth_cgi.c -o /home/user/artifacts/auth_cgi
    rm /tmp/auth_cgi.c

    cat << 'EOF' > /tmp/legit.c
#include <stdio.h>
int main() {
    printf("Content-Type: application/json\r\n\r\n{\"status\":\"ok\"}");
    return 0;
}
EOF
    gcc /tmp/legit.c -o /home/user/artifacts/legit_cgi
    rm /tmp/legit.c

    cat << 'EOF' > /home/user/build_v1_manifest.json
{
  "build_id": "v1",
  "timestamp": "2023-10-01T12:00:00Z",
  "artifacts": [
    {
      "name": "legit_cgi",
      "path": "/home/user/artifacts/legit_cgi"
    }
  ]
}
EOF

    cat << 'EOF' > /home/user/build_v2_manifest.json
{
  "build_id": "v2",
  "timestamp": "2023-10-02T12:00:00Z",
  "artifacts": [
    {
      "name": "legit_cgi",
      "path": "/home/user/artifacts/legit_cgi"
    },
    {
      "name": "auth_cgi",
      "path": "/home/user/artifacts/auth_cgi"
    }
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
