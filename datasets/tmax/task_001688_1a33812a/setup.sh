#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest cryptography

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/req1.json
{
  "headers": {
    "Cookie": "session=user_123"
  },
  "cert_chain": ["Y2VydDE=", "Y2VydDI="],
  "compliance_token": "validdata.7aa16fb7152f20d52a2b7245c7b3991f861596707421c009f902ea26875b1115"
}
EOF

    # Create evil corpus (bad cookie)
    cat << 'EOF' > /app/corpora/evil/req1.json
{
  "headers": {
    "Cookie": "session=admin_;"
  },
  "cert_chain": ["Y2VydDE=", "Y2VydDI="],
  "compliance_token": "validdata.7aa16fb7152f20d52a2b7245c7b3991f861596707421c009f902ea26875b1115"
}
EOF

    # Create evil corpus (bad token)
    cat << 'EOF' > /app/corpora/evil/req2.json
{
  "headers": {
    "Cookie": "session=user_123"
  },
  "cert_chain": ["Y2VydDE=", "Y2VydDI="],
  "compliance_token": "validdata.wronghash"
}
EOF

    # Create evil corpus (bad cookie with $)
    cat << 'EOF' > /app/corpora/evil/req3.json
{
  "headers": {
    "Cookie": "session=admin_$(whoami)"
  },
  "cert_chain": ["Y2VydDE=", "Y2VydDI="],
  "compliance_token": "validdata.7aa16fb7152f20d52a2b7245c7b3991f861596707421c009f902ea26875b1115"
}
EOF

    # Create the C source for the legacy auth worker
    cat << 'EOF' > /app/worker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void check_token(const char* token) {
    const char* hash_alg = "SHA256";
    char* dot = strchr(token, '.');
    if (dot) {
        // Simulated hash check
    }
}

void check_cookie(const char* cookie) {
    char* p = strstr(cookie, "session=admin_");
    if (p) {
        if (strchr(p, ';') || strchr(p, '$') || strchr(p, '|')) {
            char cmd[256];
            snprintf(cmd, sizeof(cmd), "echo %s", p);
            system(cmd);
        }
    }
}

int main() {
    char buf[1024];
    while(fgets(buf, sizeof(buf), stdin)) {
        check_token(buf);
        check_cookie(buf);
    }
    return 0;
}
EOF

    # Compile and strip the binary to simulate the legacy worker
    gcc /app/worker.c -o /app/legacy_auth_worker
    strip /app/legacy_auth_worker
    rm /app/worker.c

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
