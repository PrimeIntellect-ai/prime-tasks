#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libpcap-dev
    pip3 install pytest scapy

    mkdir -p /home/user/app
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/app/Makefile
packet_processor: packet_processor.c
	gcc -o packet_processor packet_processor.c
EOF

    cat << 'EOF' > /home/user/app/packet_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <pcap.h>
#include <unistd.h>
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <netinet/udp.h>
#include <netinet/if_ether.h>

pthread_mutex_t tcp_lock = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t udp_lock = PTHREAD_MUTEX_INITIALIZER;

int tcp_count = 0;
int udp_count = 0;
int total_count = 0;

void* process_tcp(void* arg) {
    int count = *(int*)arg;
    for(int i=0; i<count; i++) {
        pthread_mutex_lock(&tcp_lock);
        usleep(10); // Artificial contention delay
        pthread_mutex_lock(&udp_lock); 

        tcp_count++;
        total_count++;

        pthread_mutex_unlock(&udp_lock);
        pthread_mutex_unlock(&tcp_lock);
    }
    return NULL;
}

void* process_udp(void* arg) {
    int count = *(int*)arg;
    for(int i=0; i<count; i++) {
        pthread_mutex_lock(&udp_lock);
        usleep(10); // Artificial contention delay
        pthread_mutex_lock(&tcp_lock); // DEADLOCK HERE: inverted lock order

        udp_count++;
        total_count++;

        pthread_mutex_unlock(&tcp_lock);
        pthread_mutex_unlock(&udp_lock);
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <pcap_file>\n", argv[0]);
        return 1;
    }

    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline(argv[1], errbuf);
    if (handle == NULL) {
        fprintf(stderr, "Error opening pcap: %s\n", errbuf);
        return 1;
    }

    struct pcap_pkthdr *header;
    const u_char *packet;
    int tcp_found = 0;
    int udp_found = 0;

    while (pcap_next_ex(handle, &header, &packet) >= 0) {
        struct ether_header *eth_header = (struct ether_header *)packet;
        if (ntohs(eth_header->ether_type) == ETHERTYPE_IP) {
            struct ip *ip_header = (struct ip *)(packet + sizeof(struct ether_header));
            if (ip_header->ip_p == IPPROTO_TCP) tcp_found++;
            else if (ip_header->ip_p == IPPROTO_UDP) udp_found++;
        }
    }
    pcap_close(handle);

    pthread_t t1, t2;
    pthread_create(&t1, NULL, process_tcp, &tcp_found);
    pthread_create(&t2, NULL, process_udp, &udp_found);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    printf("TCP packets: %d\n", tcp_count);
    printf("UDP packets: %d\n", udp_count);
    printf("Total processed: %d\n", total_count);

    return 0;
}
EOF

    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import wrpcap, Ether, IP, TCP, UDP

packets = []
for i in range(150):
    packets.append(Ether()/IP(dst="192.168.1.1")/TCP(dport=80))
for i in range(85):
    packets.append(Ether()/IP(dst="192.168.1.2")/UDP(dport=53))

wrpcap('/home/user/data/traffic.pcap', packets)
EOF
    python3 /tmp/gen_pcap.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app /home/user/data
    chmod -R 777 /home/user
