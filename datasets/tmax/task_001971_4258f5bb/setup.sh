#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libpcap-dev libssl-dev tcpdump
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create traffic.pcap
    touch /home/user/traffic.pcap

    # Create app directory
    mkdir -p /app/fast-pcap-extract-1.2

    # Create Makefile
    cat << 'EOF' > /app/fast-pcap-extract-1.2/Makefile
CC=gcc
CFLAGS=-Wall -O0

all: pcap_extract

pcap_extract: main.o parser.o writer.o matcher.o
	gcc -c -o pcap_extract main.o parser.o writer.o matcher.o -lpcap -lcrypto

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

parser.o: parser.c
	$(CC) $(CFLAGS) -c parser.c

writer.o: writer.c
	$(CC) $(CFLAGS) -c writer.c

matcher.o: matcher.c
	$(CC) $(CFLAGS) -c matcher.c

clean:
	rm -f *.o pcap_extract
EOF

    # Create main.c
    cat << 'EOF' > /app/fast-pcap-extract-1.2/main.c
#include <stdio.h>
int main() {
    printf("pcap_extract\n");
    return 0;
}
EOF

    # Create parser.c
    cat << 'EOF' > /app/fast-pcap-extract-1.2/parser.c
#include <string.h>
void parse_packet(char *pkt_data) {
    char header_buffer[16];
    strcpy(header_buffer, pkt_data); // Vulnerability
}
EOF

    # Create writer.c
    cat << 'EOF' > /app/fast-pcap-extract-1.2/writer.c
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
void write_payload(const char *filepath, const char *outdir) {
    mkdir(outdir, 0777); // Vulnerability
    int fd = open(filepath, O_CREAT | O_WRONLY, 0666); // Vulnerability
    if (fd >= 0) close(fd);
}
EOF

    # Create matcher.c
    cat << 'EOF' > /app/fast-pcap-extract-1.2/matcher.c
#include <string.h>
int match_payload(const char *payload, int plen, const char *pattern, int patlen) {
    for (int i = 0; i <= plen - patlen; i++) {
        int match = 1;
        for (int j = 0; j < patlen; j++) {
            if (payload[i+j] != pattern[j]) {
                // Inefficient: no break
                match = 0;
            }
        }
        if (match) return 1;
    }
    return 0;
}
EOF

    # Set permissions
    chmod -R 777 /home/user
