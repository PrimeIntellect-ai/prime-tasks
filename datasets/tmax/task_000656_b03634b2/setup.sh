#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pcaps

    cat << 'EOF' > /home/user/generate_pcaps.py
import struct
import os

def write_pcap(filename, num_packets):
    with open(filename, 'wb') as f:
        # pcap global header (magic_number, version_major, version_minor, thiszone, sigfigs, snaplen, network)
        # Network 1 = Ethernet
        f.write(struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))
        for _ in range(num_packets):
            # pcap packet header: ts_sec, ts_usec, incl_len, orig_len
            f.write(struct.pack('<IIII', 0, 0, 14, 14))
            # Dummy ethernet frame (14 bytes)
            f.write(b'\x00\x11\x22\x33\x44\x55\x66\x77\x88\x99\xaa\xbb\x08\x00')

write_pcap('/home/user/pcaps/capture 1.pcap', 16)
write_pcap('/home/user/pcaps/capture 2.pcap', 25)
EOF

    python3 /home/user/generate_pcaps.py
    rm /home/user/generate_pcaps.py

    cat << 'EOF' > /home/user/analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

float compute_convergence(float val) {
    if (val <= 0) return 0;
    float x = val;
    float prev = 0;
    while (fabs(x - prev) > 0.001) {
        prev = x;
        x = x + (x*x - val) / (2*x); // BUG: should be minus
    }
    return x;
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char cmd[512];
    // BUG: no quotes around %s
    sprintf(cmd, "tcpdump -qnr %s 2>/dev/null | wc -l", argv[1]);

    FILE *fp = popen(cmd, "r");
    if (!fp) return 1;

    int packet_count = 0;
    fscanf(fp, "%d", &packet_count);
    pclose(fp);

    float metric = compute_convergence((float)packet_count);
    printf("File: %s, Metric: %.3f\n", argv[1], metric);

    return 0;
}
EOF

    cat << 'EOF' > /home/user/build_and_test.sh
#!/bin/bash
gcc -o analyzer analyzer.c -lm
rm -f /home/user/output.log
for f in $(ls /home/user/pcaps/*.pcap); do
    ./analyzer $f >> /home/user/output.log
done
EOF

    chmod +x /home/user/build_and_test.sh
    chmod -R 777 /home/user
