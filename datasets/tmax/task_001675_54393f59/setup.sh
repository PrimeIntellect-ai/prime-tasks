#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zip unzip flite
    pip3 install pytest SpeechRecognition pocketsphinx

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_rule(char *token) {
    char ip[256];
    int port;
    if (sscanf(token, "%255[^:]:%d", ip, &port) != 2) {
        printf("ERROR: Invalid format %s\n", token);
        return;
    }

    if (strncmp(ip, "10.", 3) == 0) {
        printf("iptables -A INPUT -s %s -p tcp --dport %d -j ACCEPT\n", ip, port);
    } else if (port < 1024) {
        printf("iptables -A INPUT -s %s -p tcp --dport %d -j REJECT --reject-with tcp-reset\n", ip, port);
    } else {
        printf("iptables -A INPUT -s %s -p tcp --dport %d -j DROP\n", ip, port);
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <IP:PORT;IP:PORT...>\n", argv[0]);
        return 1;
    }

    char *input = strdup(argv[1]);
    char *token = strtok(input, ";");

    while (token != NULL) {
        process_rule(token);
        token = strtok(NULL, ";");
    }

    free(input);
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /tmp/fw_policy_oracle
    cd /tmp
    zip -P deltanetworkseven /app/vault.zip fw_policy_oracle
    rm /tmp/oracle.c /tmp/fw_policy_oracle

    flite -t "The vault password is delta network seven." -o /app/intercepted_comms.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
