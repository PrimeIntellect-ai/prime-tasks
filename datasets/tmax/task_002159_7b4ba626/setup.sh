#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libpcap-dev wireshark-common
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/analyzer_repo
    mkdir -p /home/user/db
    mkdir -p /home/user/data

    # Setup Git Repository
    cd /home/user/analyzer_repo
    git init
    cat << 'EOF' > analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pcap.h>

void process_packet(u_char *args, const struct pcap_pkthdr *header, const u_char *packet) {
    static int frame_num = 1;
    // Bug: Segfaults if packet length is exactly 119 bytes
    if (header->caplen == 119) {
        char *ptr = NULL;
        *ptr = 'X'; // Crash!
    }
    frame_num++;
}

int main(int argc, char *argv[]) {
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle;

    if (argc != 2) {
        fprintf(stderr, "Usage: %s <pcap_file>\n", argv[0]);
        return 1;
    }

    handle = pcap_open_offline(argv[1], errbuf);
    if (handle == NULL) {
        fprintf(stderr, "Error reading pcap: %s\n", errbuf);
        return 2;
    }

    pcap_loop(handle, 0, process_packet, NULL);
    pcap_close(handle);
    printf("Processing complete.\n");
    return 0;
}
EOF
    git add analyzer.c
    git config user.name "Dev"
    git config user.email "dev@example.com"
    git commit -m "Initial commit of analyzer"

    echo "DB_DECRYPTION_KEY=v1nt4g3_k3y_99" > secret.conf
    git add secret.conf
    git commit -m "Add config for db decryption"

    git rm secret.conf
    git commit -m "Remove sensitive config file"

    # Setup SQLite DB with WAL
    cd /home/user/db
    python3 -c '
import sqlite3
import os
conn = sqlite3.connect("state.db")
conn.execute("PRAGMA journal_mode=WAL;")
conn.execute("CREATE TABLE recovery (id INTEGER, backup_token TEXT);")
conn.execute("INSERT INTO recovery VALUES (1, \"25683d2b6654706f3d6c4066010b\");")
conn.commit()
# Force exit to prevent SQLite from cleaning up the WAL file
os._exit(0)
'

    # Setup PCAP file
    cd /home/user/data
    cat << 'EOF' > make_pcap.py
from scapy.all import Ether, IP, UDP, Raw, wrpcap
packets = []
for i in range(1, 501):
    if i == 402:
        pkt = Ether(dst="00:11:22:33:44:55", src="55:44:33:22:11:00") / IP(dst="192.168.1.1", src="192.168.1.2") / UDP(sport=1234, dport=5678) / Raw(load=b"X" * 77)
    else:
        pkt = Ether(dst="00:11:22:33:44:55", src="55:44:33:22:11:00") / IP(dst="192.168.1.1", src="192.168.1.2") / UDP(sport=1234, dport=5678) / Raw(load=b"N" * 20)
    packets.append(pkt)

wrpcap("traffic.pcap", packets)
EOF
    python3 make_pcap.py
    rm make_pcap.py

    chmod -R 777 /home/user
