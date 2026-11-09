#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest flask flask-limiter

    mkdir -p /home/user/mobile_pipeline/c_src

    cat << 'EOF' > /home/user/mobile_pipeline/c_src/encoder.c
#include <string.h>

void encode_data(const char* input, char* output) {
    int len = strlen(input);
    for(int i = 0; i < len; i++) {
        output[i] = input[len - 1 - i] + 1; // Reverse and shift by 1
    }
    output[len] = '\0';
}
EOF

    cat << 'EOF' > /home/user/mobile_pipeline/c_src/Makefile
libencoder.so: encoder.o
	gcc -o libencoder.so encoder.o

encoder.o: encoder.c
	gcc -c encoder.c

clean:
	rm -f *.o *.so
EOF

    cat << 'EOF' > /home/user/mobile_pipeline/app.py
import os
import ctypes
from flask import Flask, request, jsonify

app = Flask(__name__)

# Load the shared library
lib_path = os.path.join(os.path.dirname(__file__), 'libencoder.so')
try:
    encoder_lib = ctypes.CDLL(lib_path)
    encoder_lib.encode_data.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
except Exception as e:
    pass # Will be fixed by agent once built and copied

@app.route('/encode', methods=['POST'])
def encode():
    data = request.get_json()
    text = data.get('text', '')

    # Needs validation and rate limiting...

    # Call C library
    input_bytes = text.encode('ascii')
    output_buffer = ctypes.create_string_buffer(len(input_bytes) + 1)
    encoder_lib.encode_data(input_bytes, output_buffer)

    encoded_text = output_buffer.value.decode('ascii')
    return jsonify({"encoded": encoded_text}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
