#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat
    pip3 install pytest flask

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/validator.asm
; struct manifest_header {
;     uint32_t magic;      // Must be 0x424D4F42 ("BOMB" in little-endian)
;     uint32_t version;    // Little-endian 32-bit integer
;     uint8_t  is_debug;   // 1 byte boolean
;     uint8_t  padding[3]; // 3 bytes of zero padding
; };
; Total size: 12 bytes
check_header:
    ; ... (prologue)
    cmp dword [rdi], 0x424D4F42     ; check magic
    jne .error
    mov eax, dword [rdi+4]          ; read version
    ; ... (internal version checks)
    movzx ecx, byte [rdi+8]         ; read is_debug
    ; ...
EOF

    cat << 'EOF' > /home/user/app/api.py
import socket
import struct
from flask import Flask, request, jsonify

app = Flask(__name__)

def serialize_manifest(data):
    # BUG: > means big-endian. It should be < (little-endian).
    # BUG: Magic is packed as a string, but the assembly expects a little-endian 32-bit int 0x424D4F42.
    # BUG: Padding is missing. Expected format: <I I B 3x
    magic = 0x424D4F42
    version = data.get('version_code', 0)
    is_debug = data.get('is_debug', 0)

    # CURRENT INCORRECT IMPLEMENTATION:
    return struct.pack(">I I B", magic, version, is_debug)

@app.route('/validate', methods=['POST'])
def validate():
    data = request.json
    payload = serialize_manifest(data)

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 9090))
        s.sendall(payload)
        resp = s.recv(1024)
        s.close()

        if b"OK" in resp:
            return jsonify({"status": "VALID"}), 200
        else:
            return jsonify({"status": "INVALID"}), 400
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /home/user/app/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

int main() {
    uint8_t buf[12];
    if (read(0, buf, 12) != 12) {
        printf("ERROR_SIZE\n");
        return 1;
    }

    uint32_t magic = *(uint32_t*)(buf);
    if (magic != 0x424D4F42) {
        printf("ERROR_MAGIC\n");
        return 1;
    }

    printf("OK\n");
    return 0;
}
EOF

    gcc /home/user/app/validator.c -o /home/user/app/validator

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
