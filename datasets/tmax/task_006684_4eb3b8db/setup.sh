#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/matrix.csv
1.0, 2.0, 3.0
4.0, 5.0, 6.0
7.0, 8.0, 9.0
EOF

    cat << 'EOF' > /home/user/test.patch
--- matrix.csv
+++ matrix.csv
@@ -1,3 +1,3 @@
 1.0, 2.0, 3.0
-4.0, 5.0, 6.0
+4.0, 10.0, 6.0
 7.0, 8.0, 9.0
EOF

    cat << 'EOF' > /home/user/server.py
#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
import math
import os

PORT = 8000

class MatrixRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/apply':
            # TODO: Implement the diff application and numerical computation here
            pass

if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), MatrixRequestHandler) as httpd:
        httpd.serve_forever()
EOF

    chmod +x /home/user/server.py
    chmod -R 777 /home/user
