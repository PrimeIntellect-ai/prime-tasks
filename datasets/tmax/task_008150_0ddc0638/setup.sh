#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    mkdir -p /home/user/investigation
    cd /home/user/investigation

    # 1. Create crash_report.txt
    cat << 'EOF' > crash_report.txt
Traceback (most recent call last):
  File "exfiltrator.py", line 142, in <module>
    main()
  File "exfiltrator.py", line 118, in main
    config = load_config(deleted_file_handle)
  File "exfiltrator.py", line 45, in load_config
    raise EOFError("Unexpected end of file in config")
EOFError: Unexpected end of file in config

Local variables in load_config:
  filepath = '/tmp/.hidden_cfg'
  bytes_read = 14
  partial_key = 'X7a'
  is_encrypted = True
EOF

    # 2. Create memory.dump (Raw binary file containing the key fragment)
    python3 -c "
import os
with open('memory.dump', 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b'KEY_START_b9Xz_KEY_END')
    f.write(os.urandom(2048))
"

    # 3. Create capture.pcap with valid and corrupted packets
    python3 -c "
from scapy.all import wrpcap, Ether, IP, UDP, Raw, PcapWriter
from itertools import cycle

key = b'X7ab9Xz'
flag = b'FLAG{c0r3_dump_pc4p_n1nj4_m4st3r}'
encrypted_flag = bytes(a ^ b for a, b in zip(flag, cycle(key)))
part1 = encrypted_flag[:16]
part2 = encrypted_flag[16:]

pkt1 = Ether()/IP(dst='10.0.0.2')/UDP(dport=1337)/Raw(load=part1)
pkt2 = Ether()/IP(dst='10.0.0.2')/UDP(dport=1337)/Raw(load=part2)

with PcapWriter('capture.pcap', sync=True) as writer:
    writer.write(pkt1)
    # Write a physically truncated packet header to cause EOF/struct errors in standard readers
    writer.f.write(b'\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\x00') 
    writer.write(pkt2)
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/investigation
    chmod -R 777 /home/user
