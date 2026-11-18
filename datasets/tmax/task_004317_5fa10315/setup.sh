#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump gcc make
    pip3 install pytest scapy

    mkdir -p /app
    mkdir -p /home/user

    # Generate intercepted.wav (DTMF for 8080*42)
    python3 -c '
import wave, math, struct
# DTMF frequencies
dtmf_freqs = {
    "8": (852, 1336), "0": (941, 1336), "*": (941, 1209), "4": (770, 1209), "2": (697, 1336)
}
sequence = "8080*42"
sample_rate = 8000
duration = 0.2
pause = 0.1

with wave.open("/app/intercepted.wav", "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)

    for char in sequence:
        f1, f2 = dtmf_freqs[char]
        # Tone
        for i in range(int(sample_rate * duration)):
            t = float(i) / sample_rate
            val = int(32767.0 * 0.5 * (math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)))
            w.writeframesraw(struct.pack("<h", val))
        # Pause
        for i in range(int(sample_rate * pause)):
            w.writeframesraw(struct.pack("<h", 0))
'

    # Generate traffic.pcap
    python3 -c '
from scapy.all import *
import binascii

client_payload = b"\x00\x00\x00\x08\x62\x6f\x66\x66\x65\x0a\x69\x18"
server_payload = b"\x00\x00\x00\x07\x7d\x6f\x66\x69\x65\x67\x6f"

# Create dummy TCP packets
ip = IP(src="192.168.1.100", dst="192.168.1.200")
syn = TCP(sport=12345, dport=8080, flags="S", seq=1000)
syn_ack = TCP(sport=8080, dport=12345, flags="SA", seq=2000, ack=1001)
ack = TCP(sport=12345, dport=8080, flags="A", seq=1001, ack=2001)

req = TCP(sport=12345, dport=8080, flags="PA", seq=1001, ack=2001) / Raw(load=client_payload)
resp = TCP(sport=8080, dport=12345, flags="PA", seq=2001, ack=1001+len(client_payload)) / Raw(load=server_payload)

pkts = [ip/syn, ip/syn_ack, ip/ack, ip/req, ip/resp]
wrpcap("/app/traffic.pcap", pkts)
'

    # Create broken_c2.c
    cat << 'EOF' > /home/user/broken_c2.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

#define PORT 9999 // Wrong port
#define KEY 42

void xor_crypt(char *data, int len, char key) {
    for (int i = 0; i <= len; i++) { // Off-by-one error
        data[i] ^= key;
    }
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(PORT);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }
    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            continue;
        }

        int len;
        read(new_socket, &len, 4);
        // Missing ntohl(len)

        char *buffer = malloc(len);
        read(new_socket, buffer, len);

        xor_crypt(buffer, len, KEY);

        if (strncmp(buffer, "HELLO C2", 8) == 0) {
            char *resp = "WELCOME";
            int resp_len = strlen(resp);
            char *out_buf = malloc(resp_len);
            memcpy(out_buf, resp, resp_len);
            xor_crypt(out_buf, resp_len, KEY);

            // Missing htonl for length
            write(new_socket, &resp_len, 4);
            write(new_socket, out_buf, resp_len);

            // Memory leak: out_buf not freed
        }

        // Memory leak: buffer not freed
        close(new_socket);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
