#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest flask numpy requests

    mkdir -p /app/src /app/data /app/bin

    cat << 'EOF' > /app/src/sim_server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int port = atoi(argv[1]);
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        // Generate deterministic fake data based on request length
        int req_len = strlen(buffer);
        float data[64][64];
        for(int i=0; i<64; i++) {
            for(int j=0; j<64; j++) {
                // Add a dominant frequency pattern
                data[i][j] = sin(2 * M_PI * (req_len * 3) * i / 64.0 + 2 * M_PI * 5 * j / 64.0);
            }
        }
        write(new_socket, data, 64 * 64 * sizeof(float));
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/api.py
from flask import Flask, request, jsonify
import numpy as np
import socket
import os

app = Flask(__name__)

@app.route('/analyze', methods=['GET'])
def analyze():
    # TODO: Implement token validation
    # TODO: Parse FASTA header
    # TODO: Fetch TCP data and perform 2D FFT
    return jsonify({"error": "Not implemented"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    cat << 'EOF' > /app/data/protA.fasta
>sp|P00001|CYC_MACMU Cytochrome c
MGDVEKGKKIFIMKCSQCHTVEKGGKHKTGPNLHGLFGRKTGQAPGYSYTAANKNKGIIW
GEDTLMEYLENPKKYIPGTKMIFVGIKKKEERADLIAYLKKATNE
EOF

    cat << 'EOF' > /app/data/protB.fasta
>sp|P00002|CYC_HUMAN Cytochrome c
MGDVEKGKKIFIMKCSQCHTVEKGGKHKTGPNLHGLFGRKTGQAPGYSYTAANKNKGIIW
GEDTLMEYLENPKKYIPGTKMIFVGIKKKEERADLIAYLKKATNE
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
