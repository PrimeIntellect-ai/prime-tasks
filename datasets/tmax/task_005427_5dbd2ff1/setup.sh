#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zip unzip openssl build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence
    cd /home/user

    cat << 'EOF' > server.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void handle_login(const char *request) {
    char redirect_url[256] = "/dashboard";

    // Look for redirect parameter in the query string
    const char *param = strstr(request, "target_uri=");
    if (param) {
        sscanf(param, "target_uri=%255s", redirect_url);
    }

    // VULNERABILITY: Blindly redirecting to user-supplied input (Open Redirect)
    printf("HTTP/1.1 302 Found\n");
    printf("Location: %s\n\n", redirect_url);
}

int main() {
    // Simulated request
    const char *req = "GET /login?target_uri=http://evil.com/phishing HTTP/1.1";
    handle_login(req);
    return 0;
}
EOF

    cd /home/user/evidence

    # Root CA
    openssl req -x509 -newkey rsa:2048 -keyout root_key.pem -out root.pem -days 365 -nodes -subj "/CN=LegitRootCA"
    # Intermediate CA
    openssl req -new -newkey rsa:2048 -keyout int_key.pem -out int.csr -nodes -subj "/CN=LegitIntermediateCA"

    cat << 'EOF' > extfile.cnf
basicConstraints=CA:TRUE
EOF
    openssl x509 -req -in int.csr -CA root.pem -CAkey root_key.pem -CAcreateserial -out intermediate.pem -days 365 -extfile extfile.cnf
    # Rogue Cert
    openssl req -new -newkey rsa:2048 -keyout rogue_key.pem -out rogue.csr -nodes -subj "/CN=DarkOverlord_Node"
    openssl x509 -req -in rogue.csr -CA intermediate.pem -CAkey int_key.pem -CAcreateserial -out rogue.pem -days 365

    rm -f *.key.pem *.csr *.srl extfile.cnf

    cd /home/user
    zip -P target_uri8492 evidence.zip evidence/root.pem evidence/intermediate.pem evidence/rogue.pem
    rm -rf /home/user/evidence

    chmod -R 777 /home/user
