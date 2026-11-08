#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-scapy ffmpeg gcc gawk
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate pcap with 154 TCP packets
    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import wrpcap, Ether, IP, TCP
packets = [Ether()/IP(dst="1.2.3.4")/TCP(dport=80) for _ in range(154)]
wrpcap('/app/traffic.pcap', packets)
EOF
    python3 /tmp/gen_pcap.py

    # Generate mp4 with 240 frames
    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=24 -vframes 240 -c:v libx264 -y /app/evidence.mp4

    # Create reference decoder
    cat << 'EOF' > /tmp/ref.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *hex = argv[1];
    int len = strlen(hex);
    float sum = 0;
    for (int i = 0; i < len; i += 2) {
        char buf[3] = {0};
        buf[0] = hex[i];
        if (i+1 < len) buf[1] = hex[i+1];
        int val = 0;
        sscanf(buf, "%x", &val);
        sum += val;
    }
    printf("%.4f\n", sum / 3.0);
    return 0;
}
EOF
    gcc /tmp/ref.c -o /app/reference_decoder
    chmod +x /app/reference_decoder

    # Create buggy decode.sh
    cat << 'EOF' > /home/user/decode.sh
#!/bin/bash
hex=$1
len=${#hex}
i=0
sum=0
while [ $i -lt $len ]; do
    val=${hex:$i:2}
    dec=$((16#$val))
    sum=$((sum + dec))
    # Bug: missing i=$((i+2))
done
awk -v s=$sum 'BEGIN { printf "%.0f\n", s/3 }'
EOF
    chmod +x /home/user/decode.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
