#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y ffmpeg python3-dev build-essential espeak

    # Create user
    useradd -m -s /bin/bash user || true

    # Create audio file
    mkdir -p /app/data
    espeak -w /app/data/message.wav "open the pod bay doors please hal"

    # Create service files
    mkdir -p /home/user/service

    cat << 'EOF' > /home/user/service/filter.c
#include <stdio.h>
#include <stdlib.h>
/* missing math.h */

int main(int argc, char** argv) {
    if (argc < 3) {
        prinf("Usage: %s <input> <output>\n", argv[0]); /* typo */
        return 1;
    }
    double val = sin(1.0);
    printf("Processed %s to %s with val %f\n", argv[1], argv[2], val);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/service/Makefile
filter: filter.c
	gcc -O2 -o filter filter.c
EOF

    cat << 'EOF' > /home/user/service/server.py
import BaseHTTPServer

class MyHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_GET(self):
        print "Received request for", self.path
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write("Legacy transcription service\n")

if __name__ == '__main__':
    server = BaseHTTPServer.HTTPServer(('127.0.0.1', 8888), MyHandler)
    print "Starting server on port 8888..."
    server.serve_forever()
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
