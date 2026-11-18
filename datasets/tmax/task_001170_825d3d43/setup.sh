#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/Makefile
all: db_recover

db_recover: recover.c
	gcc -g -O0 recover.c -o db_recover

clean:
	rm -f db_recover
EOF

    cat << 'EOF' > /home/user/recover.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TX 100

typedef struct {
    int id;
    int active;
    char* data;
} Transaction;

Transaction* tx_table[MAX_TX] = {NULL};

void process_command(char* cmd) {
    int id;
    char action[20];
    if (sscanf(cmd, "TX %d %s", &id, action) != 2) return;

    if (id < 0 || id >= MAX_TX) return;

    if (strcmp(action, "BEGIN") == 0) {
        if (!tx_table[id]) {
            tx_table[id] = (Transaction*)malloc(sizeof(Transaction));
            tx_table[id]->id = id;
            tx_table[id]->active = 1;
            tx_table[id]->data = (char*)malloc(256);
        }
    } else if (strcmp(action, "WRITE") == 0) {
        if (tx_table[id] && tx_table[id]->active) {
            snprintf(tx_table[id]->data, 256, "data");
        }
    } else if (strcmp(action, "ABORT") == 0 || strcmp(action, "COMMIT") == 0) {
        if (tx_table[id]) {
            free(tx_table[id]->data);
            free(tx_table[id]);
            // BUG: tx_table[id] is not set to NULL after free.
            // A second ABORT/COMMIT will cause a double free.
        }
    }
}

int main(int argc, char** argv) {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        process_command(line);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/generate_pcap.py
from scapy.all import *

commands = [
    "TX 5 BEGIN\n",
    "TX 5 WRITE A\n",
    "TX 2 BEGIN\n",
    "TX 2 WRITE B\n",
    "TX 5 ABORT\n",
    "TX 3 BEGIN\n",
    "TX 2 WRITE C\n",
    "TX 5 ABORT\n", # Double free triggers here
    "TX 2 COMMIT\n",
    "TX 3 COMMIT\n"
]

packets = []
for cmd in commands:
    pkt = IP(dst="192.168.1.10")/TCP(dport=8080)/Raw(load=cmd)
    packets.append(pkt)

wrpcap('/home/user/traffic.pcap', packets)
EOF

    python3 /home/user/generate_pcap.py
    rm /home/user/generate_pcap.py

    chmod -R 777 /home/user
