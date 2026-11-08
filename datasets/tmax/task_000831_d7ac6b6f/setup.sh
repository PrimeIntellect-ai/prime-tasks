#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service
    cd /home/user/service

    echo -n "OLD_TOKEN_123" > /home/user/service/token.txt

    cat << 'EOF' > auth_backend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char expected[64];
    FILE *f = fopen("/home/user/service/token.txt", "r");
    if (!f) return 1;
    if (fscanf(f, "%63s", expected) != 1) {
        fclose(f);
        return 1;
    }
    fclose(f);

    char *provided = getenv("APP_AUTH_SECRET");
    if (!provided) {
        if (argc > 1) {
            provided = argv[1];
        } else {
            return 1;
        }
    }

    if (strcmp(expected, provided) == 0) {
        printf("AUTH_SUCCESS\n");
        return 0;
    }
    printf("AUTH_FAIL\n");
    return 1;
}
EOF
    gcc auth_backend.c -o auth_bin
    rm auth_backend.c

    cat << 'EOF' > wrapper.py
import subprocess
import sys

TOKEN = "OLD_TOKEN_123"

def authenticate():
    result = subprocess.run(['/home/user/service/auth_bin', TOKEN], capture_output=True, text=True)
    return result.stdout.strip() == "AUTH_SUCCESS"

if __name__ == "__main__":
    if authenticate():
        print("OK")
        sys.exit(0)
    sys.exit(1)
EOF

    cat << 'EOF' > server.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess

class AuthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()

        res = subprocess.run(['python3', '/home/user/service/wrapper.py'], capture_output=True)
        if res.returncode == 0:
            self.wfile.write(b"<h1>Authenticated!</h1>")
        else:
            self.wfile.write(b"<h1>Failed</h1>")

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), AuthHandler)
    server.serve_forever()
EOF

    chown -R user:user /home/user/service
    chmod -R 777 /home/user
