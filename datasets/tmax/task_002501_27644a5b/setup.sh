#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gdb valgrind tcpdump
    pip3 install --default-timeout=100 pytest

    mkdir -p /home/user/server_src

    cat << 'EOF' > /home/user/server_src/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <math.h>

void log_message(const char* msg) {
    char buf[16];
    // Buffer overflow vulnerability
    strcpy(buf, msg);
    printf("Logged: %s\n", buf);
}

void handle_msg(const char* msg) {
    log_message(msg);
}

int main() {
    int sockfd;
    struct sockaddr_in servaddr, cliaddr;

    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = INADDR_ANY;
    servaddr.sin_port = htons(9000);

    if (bind(sockfd, (const struct sockaddr *)&servaddr, sizeof(servaddr)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    char buffer[1024];
    socklen_t len = sizeof(cliaddr);

    // Call a math function to necessitate linking against libm
    double startup_val = sqrt(256.0);
    printf("Server started (val=%.1f)\n", startup_val);

    int n = recvfrom(sockfd, (char *)buffer, 1024, MSG_WAITALL, (struct sockaddr *) &cliaddr, &len);
    buffer[n] = '\0';
    handle_msg(buffer);

    close(sockfd);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/server_src/Makefile
server: server.c
	gcc -g -o server server.c
EOF

    cat << 'EOF' > /home/user/generate_pcap.py
import struct
import time

def create_pcap(filename, payload):
    with open(filename, "wb") as f:
        # Pcap Global Header (magic, version, tz, sigfigs, snaplen, network=1 for Ethernet)
        f.write(struct.pack("<IHHIIII", 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))

        # IP / UDP packet construction
        # Dummy Ethernet header: 14 bytes
        packet = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\x00"

        # IP header: 20 bytes, protocol 17 (UDP)
        ip_len = 20 + 8 + len(payload)
        packet += b"\x45\x00" + struct.pack(">H", ip_len) + b"\x00\x00\x00\x00\x40\x11\x00\x00\x7f\x00\x00\x01\x7f\x00\x00\x01"

        # UDP header: 8 bytes, src port 12345, dst port 9000
        udp_len = 8 + len(payload)
        packet += struct.pack(">HHH", 12345, 9000, udp_len) + b"\x00\x00"

        # Payload
        packet += payload

        # Pcap Packet Header
        ts_sec = int(time.time())
        ts_usec = 0
        incl_len = len(packet)
        orig_len = len(packet)
        f.write(struct.pack("<IIII", ts_sec, ts_usec, incl_len, orig_len))
        f.write(packet)

create_pcap("/home/user/crash.pcap", b"OVERFLOW_PAYLOAD_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789")
EOF

    python3 /home/user/generate_pcap.py
    rm /home/user/generate_pcap.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/server_src /home/user/crash.pcap
    chmod -R 777 /home/user
