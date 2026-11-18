#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patch binutils
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > main.c
#include <stdio.h>
extern int calculate_hash(int val);
int main() {
    printf("Hash: %d\n", calculate_hash(10));
    return 0;
}
EOF

    cat << 'EOF' > hash.c
int calc_hsh(int val) {
    return val * 42;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
gcc main.c hash.c -o app
EOF
    chmod +x build.sh

    python3 -c '
import struct

diff_payload = """--- hash.c
+++ hash.c
@@ -1,3 +1,3 @@
-int calc_hsh(int val) {
+int calculate_hash(int val) {
     return val * 42;
 }
"""

http_payload = f"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {len(diff_payload)}\r\n\r\n{diff_payload}".encode("utf-8")

# pcap global header: magic, version_major, version_minor, thiszone, sigfigs, snaplen, network (1 = Ethernet)
global_hdr = struct.pack("<IHHIIII", 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)

# pcap packet header: ts_sec, ts_usec, incl_len, orig_len
pkt_hdr = struct.pack("<IIII", 1600000000, 0, len(http_payload), len(http_payload))

with open("traffic.pcap", "wb") as f:
    f.write(global_hdr + pkt_hdr + http_payload)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
