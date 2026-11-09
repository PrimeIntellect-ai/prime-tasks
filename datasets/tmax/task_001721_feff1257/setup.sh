#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/deployments/app1 /home/user/deployments/app2 /home/user/deployments/app3
    mkdir -p /home/user/audit
    mkdir -p /app

    echo -e "host=localhost\nport=8080" > /home/user/deployments/app1/config.ini
    echo -e "debug=true\n#old_setting=false\nworkers=4" > /home/user/deployments/app2/settings.ini
    echo -e "secret=123" > /home/user/deployments/app3/ignore.ini

    cat << 'EOF' > /home/user/audit/changes.log
---BEGIN RECORD---
File: /home/user/deployments/app1/config.ini
Timestamp: 2023-10-01T10:00:00Z
Changes:
+ port=8080
---END RECORD---
---BEGIN RECORD---
File: /home/user/deployments/app2/settings.ini
Timestamp: 2023-10-02T11:00:00Z
Changes:
+ debug=true
---END RECORD---
---BEGIN RECORD---
File: /home/user/deployments/app1/config.ini
Timestamp: 2023-10-05T15:30:00Z
Changes:
+ host=localhost
---END RECORD---
EOF

    cat << 'EOF' > /tmp/hash_checker.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    unsigned long hash = 0;
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '#') continue;
        for(int i=0; line[i]; i++) {
            if (line[i] != '\n' && line[i] != '\r') hash += line[i];
        }
    }
    fclose(f);
    printf("%lx\n", hash);
    return 0;
}
EOF
    gcc -O2 /tmp/hash_checker.c -o /app/hash_checker
    strip /app/hash_checker
    chmod +x /app/hash_checker

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

    # Fix permissions after the global chmod
    chmod 664 /home/user/deployments/app1/config.ini
    chmod 664 /home/user/deployments/app2/settings.ini
    chmod 644 /home/user/deployments/app3/ignore.ini
