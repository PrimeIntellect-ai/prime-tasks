#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project
cd /home/user/project

cat << 'EOF' > mathops.c
#include <math.h>

double compute_transform(double input) {
    return cos(input) + sin(input);
}
EOF

cat << 'EOF' > server.py
import time
import ctypes
import sys
from xmlrpc.server import SimpleXMLRPCServer

# Simulate a gRPC/RPC service wrapping a C lib
try:
    lib = ctypes.CDLL('./libmathops.so')
    lib.compute_transform.restype = ctypes.c_double
    lib.compute_transform.argtypes = [ctypes.c_double]
except OSError as e:
    print(f"Failed to load library: {e}", file=sys.stderr)
    sys.exit(1)

def compute(val):
    return lib.compute_transform(val)

server = SimpleXMLRPCServer(("localhost", 8080), allow_none=True)
server.register_function(compute, "compute")
server.serve_forever()
EOF

cat << 'EOF' > client_test.py
import xmlrpc.client
import sys
import math

try:
    proxy = xmlrpc.client.ServerProxy("http://localhost:8080/")
    val = proxy.compute(0.0)
    # cos(0) + sin(0) = 1.0
    if not math.isclose(val, 1.0, rel_tol=1e-5):
        print("Property test failed!")
        sys.exit(1)
    print("All property tests passed.")
    sys.exit(0)
except Exception as e:
    print(f"Connection/Test error: {e}")
    sys.exit(1)
EOF

cat << 'EOF' > build_and_test.sh
#!/bin/bash
cd /home/user/project

# Compile the C library
gcc -shared -o libmathops.so -fPIC mathops.c

# Start the server
python3 server.py &
SERVER_PID=$!

# Run the e2e test
python3 client_test.py

# Cleanup
kill $SERVER_PID
EOF

chmod +x build_and_test.sh
chmod -R 777 /home/user
