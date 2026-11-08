#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip libpcap-dev gcc gdb
pip3 install pytest scapy

useradd -m -s /bin/bash user || true
mkdir -p /home/user

cat << 'EOF' > /home/user/analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <pcap.h>
#include <pthread.h>
#include <unistd.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <net/ethernet.h>

pthread_mutex_t log_lock = PTHREAD_MUTEX_INITIALIZER;
int packets_processed = 0;
int finished = 0;

void *stats_thread(void *arg) {
    while(!finished) {
        usleep(500000); // sleep 0.5s
        pthread_mutex_lock(&log_lock);
        printf("Stats: %d processed\n", packets_processed);
        pthread_mutex_unlock(&log_lock);
    }
    return NULL;
}

void process_packet(u_char *args, const struct pcap_pkthdr *header, const u_char *packet) {
    struct ether_header *eth_header = (struct ether_header *) packet;
    if (ntohs(eth_header->ether_type) != ETHERTYPE_IP) return;

    const u_char *ip_header = packet + sizeof(struct ether_header);
    struct ip *iph = (struct ip *) ip_header;

    if (iph->ip_p == IPPROTO_ICMP) {
        pthread_mutex_lock(&log_lock);
        printf("ICMP Packet length: %d\n", header->len);
        if (header->len == 98) {
            printf("Special ICMP packet detected!\n");
            // BUG: Missing pthread_mutex_unlock(&log_lock);
            // This causes the main thread to hold the lock, and subsequent packets
            // or the stats thread will deadlock trying to acquire it.
            return;
        }
        packets_processed++;
        pthread_mutex_unlock(&log_lock);
        usleep(100000); // artificial delay to simulate processing
    }
}

int main() {
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline("/home/user/traffic.pcap", errbuf);
    if (handle == NULL) {
        fprintf(stderr, "Error opening pcap: %s\n", errbuf);
        return 1;
    }

    pthread_t st;
    pthread_create(&st, NULL, stats_thread, NULL);

    pcap_loop(handle, 0, process_packet, NULL);
    pcap_close(handle);

    finished = 1;
    pthread_join(st, NULL);

    printf("Total ICMP packets processed: %d\n", packets_processed);
    return 0;
}
EOF

cat << 'EOF' > /home/user/make_pcap.py
from scapy.all import *
p1 = Ether()/IP(dst="8.8.8.8")/ICMP()/Raw(b"A"*10)
p2 = Ether()/IP(dst="8.8.8.8")/ICMP()/Raw(b"B"*56)
p3 = Ether()/IP(dst="8.8.8.8")/ICMP()/Raw(b"C"*10)
wrpcap('/home/user/traffic.pcap', [p1, p2, p3])
EOF

python3 /home/user/make_pcap.py

chmod -R 777 /home/user
