#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/run_auth.sh
#!/bin/bash
./auth_service "Cookie: session=x9f8c7b6a5d4e3f2g1h0"
EOF
    chmod +x /home/user/run_auth.sh

    cat << 'EOF' > /home/user/auth_service.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Error: No cookie\n");
        return 1;
    }

    const char *cookie = argv[1];
    const char *expected = "Cookie: session=x9f8c7b6a5d4e3f2g1h0";

    if (strcmp(cookie, expected) == 0) {
        printf("Authentication successful.\n");
        return 0;
    } else {
        printf("Authentication failed.\n");
        return 1;
    }
}
EOF

    chmod -R 777 /home/user
