#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc build-essential
    pip3 install pytest scapy

    mkdir -p /home/user/math_server
    cd /home/user/math_server

    # Setup git repo
    git init
    git config user.email "dev@math.local"
    git config user.name "Dev"

    # Create the vulnerable C file
    cat << 'EOF' > math_ops.c
int gcd(int a, int b) {
    if (b == 0) return a;
    return gcd(b, a % b);
}
EOF

    git add math_ops.c
    git commit -m "Initial commit of math operations"

    # Add the secret temporarily
    cat << 'EOF' > math_ops.c
// SECRET_KEY=PROD_MATH_88492_XYZ
int gcd(int a, int b) {
    if (b == 0) return a;
    return gcd(b, a % b);
}
EOF
    git add math_ops.c
    git commit -m "Add optimization (temp)"

    # Remove the secret
    cat << 'EOF' > math_ops.c
int gcd(int a, int b) {
    if (b == 0) return a;
    return gcd(b, a % b);
}
EOF
    git add math_ops.c
    git commit -m "Clean up comments"

    # Generate PCAP file using python
    python3 -c "
from scapy.all import *
import struct
payload = struct.pack('>ii', -2147483648, -1)
pkt = IP(dst='127.0.0.1')/UDP(dport=8888, sport=12345)/Raw(load=payload)
wrpcap('/home/user/crash.pcap', pkt)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
