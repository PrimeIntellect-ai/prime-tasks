#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip socat netcat-openbsd curl jq
pip3 install pytest

mkdir -p /home/user/app/corpus/clean /home/user/app/corpus/evil /home/user/app/compose

# Clean files (proper b-prefix or encode, or no ctypes)
cat << 'EOF' > /home/user/app/corpus/clean/safe1.py
import ctypes
lib = ctypes.CDLL("lib.so")
lib.process_data(b"payload_data")
EOF

cat << 'EOF' > /home/user/app/corpus/clean/safe2.py
import ctypes
lib = ctypes.CDLL("lib.so")
data = "string".encode('utf-8')
lib.do_work(data)
EOF

# Evil files (plain string passed to lib.func)
cat << 'EOF' > /home/user/app/corpus/evil/unsafe1.py
import ctypes
lib = ctypes.CDLL("lib.so")
lib.process_data("payload_data")
EOF

cat << 'EOF' > /home/user/app/corpus/evil/unsafe2.py
import ctypes
lib = ctypes.CDLL("lib.so")
lib.do_work('another_string')
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
