#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y espeak ffmpeg expect build-essential

    mkdir -p /app
    espeak -w /tmp/temp.wav "System alert. The authorization code is nine four two eight."
    ffmpeg -i /tmp/temp.wav -ar 16000 -ac 1 /app/incident_alert.wav
    chmod 644 /app/incident_alert.wav

    cat << 'EOF' > /tmp/fw_unlock.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char input[10];
    printf("Please enter the emergency voice PIN: ");
    fflush(stdout);
    if (fgets(input, 10, stdin) != NULL) {
        input[strcspn(input, "\r\n")] = 0;
        if (strcmp(input, "9428") == 0) {
            printf("Firewall unlocked.\n");
            FILE *f = fopen("/tmp/fw_unlocked", "w");
            if(f) { fprintf(f, "UNLOCKED\n"); fclose(f); }
            return 0;
        } else {
            printf("Invalid PIN.\n");
            return 1;
        }
    }
    return 1;
}
EOF
    gcc /tmp/fw_unlock.c -o /app/fw_unlock
    chmod 755 /app/fw_unlock

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
