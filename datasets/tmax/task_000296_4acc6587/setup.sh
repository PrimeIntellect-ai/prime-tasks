#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libpcap-dev g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_pcap.py
import struct
import time

def make_pcap():
    with open('/home/user/capture.pcap', 'wb') as f:
        # pcap global header (little endian, ethernet)
        f.write(struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))

        def write_pkt(payload):
            # mock ether/ip/udp headers
            eth = b'\x00'*12 + b'\x08\x00'
            ip = b'\x45\x00' + struct.pack('>H', 20+8+len(payload)) + b'\x00'*5 + b'\x11' + b'\x00'*10
            udp = b'\x04\xd2\x23\x28' + struct.pack('>H', 8+len(payload)) + b'\x00\x00'
            data = eth + ip + udp + payload
            ts_sec = int(time.time())
            ts_usec = 0
            incl_len = len(data)
            orig_len = len(data)
            f.write(struct.pack('<IIII', ts_sec, ts_usec, incl_len, orig_len))
            f.write(data)

        def make_payload(symbol, seq, amount=None):
            p = symbol.encode('ascii')[:4].ljust(4, b'\0')
            p += struct.pack('<I', seq)
            if amount is not None:
                p += struct.pack('<d', amount)
            return p

        write_pkt(make_payload("AAPL", 1, 10000000.0))
        write_pkt(make_payload("AAPL", 2, 0.25))
        write_pkt(make_payload("AAPL", 3, 0.25))
        write_pkt(make_payload("MSFT", 4)) # Corrupted! Length 8
        write_pkt(make_payload("MSFT", 5, 500.0))
        write_pkt(make_payload("TSLA", 6, 120.5))
        write_pkt(make_payload("GOOG", 7)) # Corrupted! Length 8

make_pcap()
EOF

    python3 /home/user/generate_pcap.py

    cat << 'EOF' > /home/user/queries.txt
AAPL
MSFT
TSLA
EOF

    cat << 'EOF' > /home/user/trade_aggregator.cpp
#include <iostream>
#include <fstream>
#include <map>
#include <string>
#include <vector>
#include <pcap.h>

std::map<std::string, float> aggregates;

void packet_handler(u_char *args, const struct pcap_pkthdr *header, const u_char *packet) {
    // Skip Ether (14), IP (20), UDP (8)
    const u_char *payload = packet + 14 + 20 + 8;
    int payload_len = header->caplen - 14 - 20 - 8;

    char sym[5] = {0};
    for(int i=0; i<4; i++) sym[i] = payload[i];

    uint32_t seq = *(uint32_t*)(payload + 4);

    // BUG: Corrupted input handling missing
    double amount = *(double*)(payload + 8);

    // BUG: Precision loss
    aggregates[sym] += (float)amount;
}

int main() {
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline("/home/user/capture.pcap", errbuf);
    if (handle == nullptr) {
        std::cerr << "Error: " << errbuf << std::endl;
        return 1;
    }
    pcap_loop(handle, 0, packet_handler, nullptr);
    pcap_close(handle);

    // BUG: hardcoded output, should read from queries.txt and write to results.log
    std::cout << "AAPL: " << aggregates["AAPL"] << std::endl;
    std::cout << "MSFT: " << aggregates["MSFT"] << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
