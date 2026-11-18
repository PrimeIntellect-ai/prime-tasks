#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc make socat netcat-openbsd
    pip3 install pytest

    mkdir -p /app

    # Create oracle processor
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#define SECRET_KEY 0xDEADBEEF
int main() {
    unsigned long hash = 5381;
    int c;
    while ((c = getchar()) != EOF) {
        hash = (hash * 31 + c) ^ SECRET_KEY;
    }
    printf("%lu\n", hash);
    return 0;
}
EOF
    gcc -o /app/oracle_processor /tmp/oracle.c
    rm /tmp/oracle.c
    chmod +x /app/oracle_processor

    # Create backend repo
    mkdir -p /app/backend-repo
    cd /app/backend-repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > secret.h
#define SECRET_KEY 0xDEADBEEF
EOF

    cat << 'EOF' > processor.c
#include <stdio.h>
#include <math.h>
#include "secret.h"

int main() {
    unsigned long hash = 5381;
    int c;
    double x = sqrt(16.0); // Requires -lm to link
    while ((c = getchar()) != EOF) {
        hash = (hash * 13 + c) | SECRET_KEY;
    }
    printf("%lu\n", hash);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all:
	gcc -o backend_processor processor.c
EOF

    git add secret.h processor.c Makefile
    git commit -m "Initial commit"

    # Remove secret key to simulate the mistake
    rm secret.h
    sed -i 's/#include "secret.h"//' processor.c
    git add processor.c
    git rm secret.h
    git commit -m "Oops, removed secret key"

    # Create frontend script
    cat << 'EOF' > /app/frontend.sh
#!/bin/bash
read FILENAME
cat $FILENAME | nc 127.0.0.1 8001
EOF
    chmod +x /app/frontend.sh

    # Create start services script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
socat TCP-LISTEN:8000,fork,reuseaddr EXEC:/app/frontend.sh &
socat TCP-LISTEN:8002,fork,reuseaddr EXEC:/app/backend-repo/backend_processor &
wait
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
