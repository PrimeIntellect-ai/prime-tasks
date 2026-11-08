#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
pip3 install pytest scapy cython numpy

mkdir -p /home/user/workspace
cd /home/user/workspace

cat << 'EOF' > decoder.pyx
import numpy as np
cimport numpy as np

def decode(np.ndarray[np.int64_t, ndim=1] data):
    cdef long total = 0
    cdef int i
    for i in range(data.shape[0]):
        total += data[i] * (i + 1)
    return total % 9973
EOF

cat << 'EOF' > setup.py
from setuptools import setup
from Cython.Build import cythonize
import numpy as np

setup(
    ext_modules=cythonize("decoder.pyx"),
    # The agent needs to add: include_dirs=[np.get_include()]
)
EOF

cat << 'EOF' > generate_pcap.py
from scapy.all import IP, TCP, Ether, wrpcap
import json

payload = json.dumps([4815, 162342, 31415, 9265, 3589])
pkt = Ether()/IP(dst="192.168.1.100")/TCP(dport=8080)/payload

wrpcap("traffic.pcap", [pkt])
EOF

python3 generate_pcap.py
rm generate_pcap.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
