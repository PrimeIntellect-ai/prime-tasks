#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

    # Prevent tshark from prompting during installation
    echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections

    apt-get update && apt-get install -y python3 python3-pip python3-scapy tshark bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ticket_8841
    cd /home/user/ticket_8841

    cat << 'EOF' > process_data.sh
#!/bin/bash
INPUT_FILE=$1
OUTPUT_FILE="final_averages.txt"

> "$OUTPUT_FILE"
> intermediate_state.log

declare -A sum
declare -A count

while IFS=, read -r sensor_id value; do
    # Log intermediate state
    echo "Processing $sensor_id : $value" >> intermediate_state.log

    # Bug 1: Crash on empty/malformed value
    # Bug 2: Bash integer arithmetic causes precision loss. value is cast to int, sum drops decimals.
    int_val=${value%.*} # strips decimal

    sum[$sensor_id]=$(( ${sum[$sensor_id]:-0} + int_val ))
    count[$sensor_id]=$(( ${count[$sensor_id]:-0} + 1 ))

done < "$INPUT_FILE"

for id in "${!sum[@]}"; do
    # Bug 3: Integer division for average
    avg=$(( ${sum[$id]} / ${count[$id]} ))
    echo "$id:$avg" >> "$OUTPUT_FILE"
done

# Sort the output
sort -o "$OUTPUT_FILE" "$OUTPUT_FILE"
EOF
    chmod +x process_data.sh

    cat << 'EOF' > container.log
[INFO] Starting data processing pipeline...
[INFO] Reading payloads...
Processing S1 : 12.45
Processing S2 : 98.22
process_data.sh: line 17: +  : syntax error: operand expected (error token is "+  ")
[ERROR] Container crashed with exit code 1.
EOF

    cat << 'EOF' > generate_pcap.py
import struct
from scapy.all import Ether, IP, UDP, wrpcap

packets = []
payloads = [
    b"S1,10.50",
    b"S2,20.25",
    b"S1,15.75",
    b"MALFORMED_DATA", # Causes the crash in the bash script
    b"S2,30.75",
    b"S3,100.00",
    b"S3,100.05"
]

for p in payloads:
    pkt = Ether()/IP(dst="192.168.1.100")/UDP(dport=8080)/p
    packets.append(pkt)

wrpcap("traffic.pcap", packets)
EOF

    python3 generate_pcap.py
    rm generate_pcap.py

    chmod -R 777 /home/user
