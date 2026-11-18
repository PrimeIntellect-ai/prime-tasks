#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        char *p1 = strstr(buffer, "AUTH_PAYLOAD=");
        if (p1 != NULL) {
            char *p2 = strstr(p1, "0xDEADC0DE");
            if (p2 != NULL) {
                abort();
            }
        }
    }
    return 0;
}
EOF

    gcc -O2 -s -o /app/log_validator /app/main.c
    chmod +x /app/log_validator

    python3 -c "
import os, random
random.seed(42)
os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

normal_logs = [
    'Jan 10 10:00:00 server sshd[123]: Accepted publickey for user\n',
    'Jan 10 10:01:00 server kernel: [ 100.0] eth0: link up\n',
    'Jan 10 10:02:00 server app: AUTH_PAYLOAD=0x1A2B3C\n'
]

evil_payloads = [
    'Jan 10 10:03:00 server app: AUTH_PAYLOAD= 0xDEADC0DE\n',
    'Jan 10 10:04:00 server app: AUTH_PAYLOAD=   0xDEADC0DE\n'
]

for i in range(50):
    with open(f'/app/corpus/clean/log_{i}.txt', 'w') as f:
        f.writelines(random.choices(normal_logs, k=20))

for i in range(50):
    with open(f'/app/corpus/evil/log_{i}.txt', 'w') as f:
        lines = random.choices(normal_logs, k=20) + random.choices(evil_payloads, k=random.randint(1, 5))
        random.shuffle(lines)
        f.writelines(lines)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
