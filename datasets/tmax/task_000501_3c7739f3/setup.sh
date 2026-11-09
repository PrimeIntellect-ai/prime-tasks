#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libpcap-dev gcc make
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/forensics

    # Generate PCAP using Python and Scapy
    cat << 'EOF' > /home/user/forensics/gen_pcap.py
from scapy.all import IP, UDP, Ether, wrpcap
import struct
import time

packets = []
values = [
    1000000.01,
    1000000.02,
    1000000.03,
    1000000.01,
    1000000.02,
    1000000.05,
    1000000.01,
    1000000.04,
    1000000.02,
    1000000.03
]

ts_base = int(time.time())

for i, val in enumerate(values):
    payload = f"[Pressure Sensor A] {val:.2f} {ts_base + i}".encode('utf-8')
    pkt = Ether()/IP(dst="127.0.0.1")/UDP(dport=9000, sport=12345)/payload
    packets.append(pkt)

wrpcap('/home/user/forensics/traffic.pcap', packets)
EOF
    python3 /home/user/forensics/gen_pcap.py

    # Write Makefile
    cat << 'EOF' > /home/user/forensics/Makefile
all:
	gcc -o telemetry_parser telemetry_parser.c -lpcap
EOF

    # Write Buggy C code
    cat << 'EOF' > /home/user/forensics/telemetry_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pcap.h>
#include <netinet/in.h>
#include <netinet/if_ether.h>
#include <netinet/ip.h>
#include <netinet/udp.h>

char target_sensor[256] = "";
long count = 0;
double sum = 0.0;
double sum_sq = 0.0;

void packet_handler(u_char *user_data, const struct pcap_pkthdr *pkthdr, const u_char *packet) {
    struct ip *iph = (struct ip *)(packet + 14); // skip ethernet
    if (iph->ip_p == IPPROTO_UDP) {
        int ip_len = iph->ip_hl * 4;
        struct udphdr *udph = (struct udphdr *)((u_char *)iph + ip_len);

        if (ntohs(udph->dest) == 9000) {
            char *payload = (char *)udph + 8;
            int payload_len = ntohs(udph->len) - 8;

            char buffer[512];
            if (payload_len < sizeof(buffer)) {
                memcpy(buffer, payload, payload_len);
                buffer[payload_len] = '\0';

                char sensor_name[256];
                double value;
                long timestamp;

                // BUG 1: %s stops at space, failing to parse names like "Pressure Sensor A"
                if (sscanf(buffer, "[%s] %lf %ld", sensor_name, &value, &timestamp) == 3) {
                    if (count == 0) {
                        strcpy(target_sensor, sensor_name);
                    }

                    count++;
                    sum += value;
                    sum_sq += (value * value); // BUG 2: Catastrophic cancellation
                }
            }
        }
    }
}

int main() {
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline("traffic.pcap", errbuf);

    if (handle == NULL) {
        fprintf(stderr, "Error opening pcap: %s\n", errbuf);
        return 1;
    }

    pcap_loop(handle, 0, packet_handler, NULL);
    pcap_close(handle);

    if (count > 1) {
        double mean = sum / count;
        double variance = (sum_sq - (sum * sum / count)) / (count - 1);

        printf("Sensor: %s\n", target_sensor);
        printf("Count: %ld\n", count);
        printf("Mean: %.2f\n", mean);
        printf("Variance: %.4f\n", variance);
    } else {
        printf("Not enough data.\n");
    }
    return 0;
}
EOF

    chown -R user:user /home/user/forensics
    chmod -R 777 /home/user
