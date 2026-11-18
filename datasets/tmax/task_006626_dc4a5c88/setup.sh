#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl
    pip3 install pytest PyJWT cryptography

    mkdir -p /home/user

    cat << 'EOF' > /home/user/target_beacon.c
#include <stdio.h>
#include <string.h>

int main() {
    // Obfuscated a bit to prevent simple string dumping without standard tools, 
    // but strings will still easily catch the static variables.
    static const char* jwt_secret = "SECRET_KEY_JWT=SuperSecretRedTeamK3y!";
    static const char* expected_cn = "EXPECTED_CN=c2.evil-corp.local";

    char buffer[256];
    snprintf(buffer, sizeof(buffer), "Initializing beacon with %s and %s", jwt_secret, expected_cn);

    // Dummy logic
    if (strlen(buffer) > 1000) {
        printf("Error\n");
    }
    return 0;
}
EOF

    gcc /home/user/target_beacon.c -o /home/user/target_beacon
    rm /home/user/target_beacon.c
    chmod +x /home/user/target_beacon

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
