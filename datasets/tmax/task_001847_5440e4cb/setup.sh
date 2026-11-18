#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ffi
    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/ffi/sec_check.c
#include <string.h>

int check_vulnerability(const char* pkg, const char* version) {
    if (strcmp(pkg, "auth-utils") == 0 && strcmp(version, "1.2.0") == 0) return 1;
    if (strcmp(pkg, "form-parser") == 0 && strcmp(version, "0.9.4") == 0) return 1;
    if (strcmp(pkg, "dev-server") == 0 && strcmp(version, "1.0.0") == 0) return 1; // Vulnerable but in Dev-Tools!
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/secure-lock.txt
BEGIN [System]
  fs-extra 9.0.1
  path-lib 2.1.0
END [System]
BEGIN [Web-Components]
  auth-utils 1.2.0
  ui-buttons 3.0.0
  form-parser 0.9.4
  express-router 4.1.0
END [Web-Components]
BEGIN [Dev-Tools]
  dev-server 1.0.0
  linter 8.0.2
END [Dev-Tools]
EOF

    cat << 'EOF' > /home/user/project/package.json
{
  "name": "legacy-web",
  "version": "1.0.0",
  "dependencies": {
    "auth-utils": "^1.2.0",
    "express-router": "4.1.0"
  },
  "peerDependencies": {
    "form-parser": "0.9.4"
  }
}
EOF

    chmod -R 777 /home/user
