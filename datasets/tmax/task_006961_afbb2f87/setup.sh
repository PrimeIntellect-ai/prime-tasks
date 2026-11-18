#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/mda_setup/src
    mkdir -p /tmp/mda_setup/scripts

    cat << 'EOF' > /tmp/mda_setup/src/mailer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int sock = 0;
    struct sockaddr_in serv_addr;
    char buffer[1024] = {0};

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        printf("Socket creation error\n");
        return -1;
    }

    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(9050);

    if(inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr)<=0) {
        printf("Invalid address\n");
        return -1;
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        printf("Connection Failed. Backend service not ready.\n");
        return 1;
    }

    read(sock, buffer, 1024);

    FILE *f = fopen("/home/user/success.log", "w");
    if (f != NULL) {
        fprintf(f, "[SUCCESS] Loaded %s users from backup\n", buffer);
        fclose(f);
    }

    printf("Mail agent started successfully.\n");
    return 0;
}
EOF

    cat << 'EOF' > /tmp/mda_setup/mock_db.sh
#!/bin/bash
# Simulates a slow-starting database/config service
sleep 3
# Listen on port 9050 and send the number 854
echo -n "854" | nc -l -p 9050 -q 1
EOF
    chmod +x /tmp/mda_setup/mock_db.sh

    cat << 'EOF' > /tmp/mda_setup/start_all.sh
#!/bin/bash
# Launch the backend service in the background
/home/user/restore/mock_db.sh &

# BUG: Starts immediately before port 9050 is open
/home/user/restore/bin/mailer
EOF
    chmod +x /tmp/mda_setup/start_all.sh

    cd /tmp/mda_setup
    tar -czf /home/user/mda_backup.tar.gz *
    rm -rf /tmp/mda_setup

    chmod -R 777 /home/user
