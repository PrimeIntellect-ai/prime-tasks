#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libpcap-dev curl libcurl4-openssl-dev
    pip3 install pytest flask scapy

    mkdir -p /home/user/app/emitter
    mkdir -p /home/user/app/aggregator
    mkdir -p /home/user/app/daemon
    mkdir -p /home/user/app/lib/mock_include

    cat << 'EOF' > /home/user/app/emitter/stream.py
import sys
import time
import socket
import struct
from scapy.all import rdpcap, TCP, Raw

if len(sys.argv) < 2:
    print("Usage: stream.py <pcap_file>")
    sys.exit(1)

pcap_file = sys.argv[1]
packets = rdpcap(pcap_file)

server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server_socket.bind(('0.0.0.0', 9000))
server_socket.listen(1)

print("Emitter listening on port 9000...")
conn, addr = server_socket.accept()
print(f"Connected by {addr}")

for pkt in packets:
    if TCP in pkt and Raw in pkt:
        payload = pkt[Raw].load
        header = struct.pack("!I", len(payload))
        try:
            conn.sendall(header + payload)
            time.sleep(0.001)
        except Exception as e:
            print("Connection closed")
            break

time.sleep(1)
conn.close()
server_socket.close()
EOF

    cat << 'EOF' > /home/user/app/aggregator/server.py
from flask import Flask, request
import json

app = Flask(__name__)

@app.route('/', methods=['POST'])
def log_tlv():
    data = request.get_json()
    if data:
        with open('/home/user/app/aggregator/parsed_tlvs.log', 'a') as f:
            f.write(json.dumps(data) + '\n')
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    cat << 'EOF' > /home/user/app/daemon/Makefile
CC = gcc
CFLAGS = -Wall -g -I../lib/mock_include
LDFLAGS = -L../lib/ -lpcap-mock -lcurl

all: dpi_daemon

dpi_daemon: main.o parser.o
	$(CC) -o dpi_daemon main.o parser.o $(LDFLAGS)

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

parser.o: parser.c
	$(CC) $(CFLAGS) -c parser.c

clean:
	rm -f *.o dpi_daemon
EOF

    cat << 'EOF' > /home/user/app/daemon/parser.h
#ifndef PARSER_H
#define PARSER_H

#include <stdint.h>

int parse_tlv(const uint8_t *data, int total_length);

#endif
EOF

    cat << 'EOF' > /home/user/app/daemon/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <curl/curl.h>
#include "parser.h"

void post_to_aggregator(uint8_t type, int tlv_len) {
    CURL *curl;
    CURLcode res;
    char payload[128];

    snprintf(payload, sizeof(payload), "{\"tlv_type\": %d, \"tlv_len\": %d}", type, tlv_len);

    curl = curl_easy_init();
    if(curl) {
        struct curl_slist *headers = NULL;
        headers = curl_slist_append(headers, "Content-Type: application/json");

        curl_easy_setopt(curl, CURLOPT_URL, "http://127.0.0.1:8080/");
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

        res = curl_easy_perform(curl);

        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
    }
}

int parse_tlv(const uint8_t *data, int total_length) {
    if (total_length <= 0) return 0;
    if (total_length < 3) return -1;

    uint8_t type = data[0];
    int tlv_len = (data[1] << 8) | data[2];

    int remaining = total_length - 3;
    short declared_len = (short)tlv_len; 

    if (declared_len > remaining) {
        return -1;
    }

    post_to_aggregator(type, declared_len);

    return 1 + parse_tlv(data + 3 + declared_len, remaining - declared_len);
}
EOF

    cat << 'EOF' > /home/user/app/daemon/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <pcap.h>
#include "parser.h"

int main() {
    int sock;
    struct sockaddr_in server;
    uint32_t payload_len;
    uint8_t buffer[65536];

    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock == -1) {
        perror("Could not create socket");
        return 1;
    }

    server.sin_addr.s_addr = inet_addr("127.0.0.1");
    server.sin_family = AF_INET;
    server.sin_port = htons(9000);

    while(connect(sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
        usleep(100000);
    }

    while(1) {
        if (recv(sock, &payload_len, 4, MSG_WAITALL) != 4) break;
        payload_len = ntohl(payload_len);
        if (payload_len > sizeof(buffer)) break;
        if (recv(sock, buffer, payload_len, MSG_WAITALL) != payload_len) break;

        parse_tlv(buffer, payload_len);
    }

    close(sock);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/lib/mock_include/pcap.h
#ifndef MOCK_PCAP_H
#define MOCK_PCAP_H
#error "Using mock pcap.h instead of system pcap.h!"
#endif
EOF

    cat << 'EOF' > /home/user/app/generate_pcap.py
from scapy.all import IP, TCP, Ether, wrpcap
import struct

packets = []
for i in range(5000):
    if i == 120:
        # Malicious packet: type 1, length 0xFFFE (65534)
        payload = struct.pack("!B H", 1, 0xFFFE) + b"A"*10
    else:
        # Normal packet: type 1, length 5
        payload = struct.pack("!B H", 1, 5) + b"A"*5

    pkt = Ether()/IP(dst="127.0.0.1")/TCP(dport=80)/payload
    packets.append(pkt)

wrpcap('/home/user/app/traffic.pcap', packets)
EOF

    python3 /home/user/app/generate_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
