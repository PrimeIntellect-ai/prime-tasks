#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_pcap.py
import struct

def write_pcap(filename):
    with open(filename, 'wb') as f:
        # PCAP global header
        f.write(struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))

        def write_packet(payload):
            # dummy eth+ip+udp = 42 bytes
            header = b'\x00'*42
            pkt = header + payload
            incl_len = len(pkt)
            orig_len = incl_len
            f.write(struct.pack('<IIII', 0, 0, incl_len, orig_len))
            f.write(pkt)

        # Pkt 1: Type 1, ID=10, Val=25
        write_packet(struct.pack('>BII', 1, 10, 25))
        # Pkt 2: Type 2, N=2, msg="OK"
        write_packet(struct.pack('>BB2s', 2, 2, b'OK'))
        # Pkt 3: Type 2, N=50, msg="ERR" (truncated to 3 bytes)
        write_packet(struct.pack('>BB3s', 2, 50, b'ERR'))
        # Pkt 4: Type 1, ID=12, Val=26
        write_packet(struct.pack('>BII', 1, 12, 26))

write_pcap('/home/user/traffic.pcap')
EOF

    python3 /home/user/create_pcap.py
    rm /home/user/create_pcap.py

    cat << 'EOF' > /home/user/parse_pcap.py
import struct
import sys

def parse_pcap(filename):
    with open(filename, 'rb') as f:
        global_header = f.read(24)
        while True:
            pkthdr = f.read(16)
            if not pkthdr:
                break
            ts_sec, ts_usec, incl_len, orig_len = struct.unpack('<IIII', pkthdr)
            packet_data = f.read(incl_len)

            # Skip Ethernet (14) + IPv4 (20) + UDP (8) = 42 bytes
            payload = packet_data[42:]
            if not payload:
                continue

            msg_type = payload[0]
            if msg_type == 1:
                sensor_id, value = struct.unpack('>II', payload[1:9])
                print(f"Sensor {sensor_id}: {value}")
            elif msg_type == 2:
                n = payload[1]
                msg = struct.unpack(f'>{n}s', payload[2:2+n])[0]
                print(f"Status: {msg.decode('ascii')}")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python parse_pcap.py <file>")
        sys.exit(1)
    parse_pcap(sys.argv[1])
EOF

    chmod -R 777 /home/user
