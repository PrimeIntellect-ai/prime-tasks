#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace tcpdump tshark
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the hidden target file
    echo -n "SECRET_DATA_99" > /home/user/.conf_7781a

    # Create the buggy C source code
    cat << 'EOF' > /home/user/malware.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

void get_target_file(char *buf) {
    // Obfuscated path building
    char part1[] = "/home/user/";
    char part2[] = ".conf_7781a";
    strcpy(buf, part1);
    strcat(buf, part2);
}

int main() {
    char filepath[256];
    get_target_file(filepath);

    int fd = open(filepath, O_RDONLY);
    if (fd < 0) {
        return 1;
    }

    char data[64] = {0};
    read(fd, data, 63);
    close(fd);

    int len = strlen(data);

    // BUG: Off-by-one error. Size is 10, but loop calculates up to index 10 (11th element).
    // This corrupts adjacent memory.
    unsigned char fib[10];
    fib[0] = 1;
    fib[1] = 1;
    for(int i = 2; i <= 10; i++) {
        fib[i] = fib[i-1] + fib[i-2];
    }

    // Encoding loop
    for(int i = 0; i < len; i++) {
        unsigned char encoded = data[i] + fib[i % 10];
        printf("%02x", encoded);
    }
    printf("\n");

    return 0;
}
EOF

    # Create a valid PCAP file with a TCP SYN packet to port 8443
    python3 -c '
import struct
import binascii

pcap_global_header = struct.pack("<IHHIIII", 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)

# Ethernet (14) + IPv4 (20) + TCP (20)
packet_data = binascii.unhexlify(
    "0000000000000000000000000800" + 
    "450000280001000040067cbcc0a8010a0a000005" + 
    "303920fb00000000000000005002200025730000"
)

pcap_packet_header = struct.pack("<IIII", 1600000000, 0, len(packet_data), len(packet_data))

with open("/home/user/traffic.pcap", "wb") as f:
    f.write(pcap_global_header)
    f.write(pcap_packet_header)
    f.write(packet_data)
'

    chmod 644 /home/user/traffic.pcap
    chmod 644 /home/user/malware.c
    chmod 644 /home/user/.conf_7781a

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
