#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ tshark tcpdump
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import struct

pcap_header = struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)

def make_ip_tcp_packet(src_ip, dst_ip, payload):
    ip_header = b'\x45\x00' + struct.pack('>H', 40 + len(payload)) + b'\x00\x00\x40\x00\x40\x06\x00\x00'
    ip_header += bytes(map(int, src_ip.split('.')))
    ip_header += bytes(map(int, dst_ip.split('.')))

    tcp_header = struct.pack('>HHIIBBHHH', 12345, 9000, 1, 1, 0x50, 0x18, 0x2000, 0, 0)
    packet_data = b'\x00\x11\x22\x33\x44\x55\x66\x77\x88\x99\xaa\xbb\x08\x00' + ip_header + tcp_header + payload

    ts_sec, ts_usec = 1600000000, 0
    incl_len = orig_len = len(packet_data)
    pcap_rec_header = struct.pack('<IIII', ts_sec, ts_usec, incl_len, orig_len)

    return pcap_rec_header + packet_data

with open('/home/user/traffic.pcap', 'wb') as f:
    f.write(pcap_header)
    f.write(make_ip_tcp_packet('192.168.1.10', '10.0.0.5', b'HELLO'))
    f.write(make_ip_tcp_packet('10.55.201.77', '10.0.0.5', b'POISON_PILL'))

def create_wal_record(opcode, key, value, corrupt=False):
    key_bytes = key.encode('ascii')
    val_bytes = value.encode('ascii')

    payload = struct.pack('<B B', opcode, len(key_bytes)) + key_bytes + struct.pack('<H', len(val_bytes)) + val_bytes

    checksum = 0
    for b in payload:
        checksum ^= b

    if corrupt:
        checksum ^= 0xFF

    record_len = len(payload) + 1

    return b'KVLG' + struct.pack('<I', record_len) + payload + struct.pack('<B', checksum)

with open('/home/user/server.wal', 'wb') as f:
    f.write(create_wal_record(1, 'config_host', 'db.internal.net'))
    f.write(create_wal_record(1, 'max_connections', '1024'))
    f.write(create_wal_record(2, 'DELETE_ME', ''))
    f.write(create_wal_record(1, 'timeout_ms', '5000'))

    f.write(create_wal_record(1, 'poison_flag', 'true', corrupt=True))

    partial_record = create_wal_record(1, 'lost_key', 'lost_value')
    f.write(partial_record[:10])
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
