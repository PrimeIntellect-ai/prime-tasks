#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate certificate
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/key.pem -out /home/user/cert.pem -days 365 -nodes -subj "/CN=vulnerable.localnetwork.com"

    # Create dummy logger
    cat << 'EOF' > /home/user/dummy_logger.sh
#!/bin/bash
# Dummy logger
sleep 0.5
EOF
    chmod +x /home/user/dummy_logger.sh

    # Create vulnerable service
    cat << 'EOF' > /home/user/cert_service.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    while(1) {
        system("/usr/bin/openssl verify /home/user/cert.pem > /dev/null 2>&1");
        // Spawns the logger with the leaked token
        system("/bin/bash -c '/home/user/dummy_logger.sh TOKEN_77X92_BETA_LEAK' > /dev/null 2>&1 &");
        sleep(3);
    }
    return 0;
}
EOF

    # Compile the service
    gcc /home/user/cert_service.c -o /home/user/cert_service

    chmod -R 777 /home/user
