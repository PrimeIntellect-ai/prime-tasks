#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest scapy

    mkdir -p /home/user
    cd /home/user

    # Create the buggy beacon source code
    cat << 'EOF' > beacon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

#define PORT 8888
#define MAX_BUFFER 1024

// TLV Protocol:
// [1 byte Type] (0x01 = Ping, 0x02 = Exec)
// [2 bytes Length] (Little Endian)
// [Length bytes Value]

int main() {
    int sockfd;
    struct sockaddr_in server_addr, client_addr;
    char buffer[MAX_BUFFER];
    socklen_t addr_len = sizeof(client_addr);

    if ((sockfd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
        perror("Socket creation failed");
        exit(EXIT_FAILURE);
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(PORT);

    if (bind(sockfd, (const struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        perror("Bind failed");
        exit(EXIT_FAILURE);
    }

    printf("Beacon listening on UDP %d...\n", PORT);

    while (1) {
        int n = recvfrom(sockfd, buffer, MAX_BUFFER, 0, (struct sockaddr *)&client_addr, &addr_len);
        if (n < 3) continue;

        unsigned char type = buffer[0];
        unsigned short length = (unsigned char)buffer[1] | ((unsigned char)buffer[2] << 8);

        if (n < 3 + length) continue;

        if (type == 0x02) { // Exec command
            char cmd[MAX_BUFFER];
            memset(cmd, 0, MAX_BUFFER);

            // BUG: Stops reading at the first space!
            sscanf(buffer + 3, "%s", cmd);

            printf("Executing: %s\n", cmd);
            system(cmd);
        }
    }
    return 0;
}
EOF

    # Create a PCAP file with a valid payload (Type=0x02, Length=2, Value="ls")
    python3 -c '
from scapy.all import *
payload = b"\x02\x02\x00ls"
pkt = IP(dst="127.0.0.1")/UDP(dport=8888)/Raw(load=payload)
wrpcap("traffic.pcap", [pkt])
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
