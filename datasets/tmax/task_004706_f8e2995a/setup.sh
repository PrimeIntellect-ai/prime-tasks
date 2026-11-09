#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make procps
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/src

    cat << 'EOF' > /home/user/app/src/crypto.c
int do_crypto(int val) {
    return val * 2;
}
EOF

    cat << 'EOF' > /home/user/app/src/token.c
#include <string.h>
extern int do_crypto(int val);

int verify_token(const char* serialized_data) {
    char user[16];
    // BUG: Buffer overflow
    strcpy(user, serialized_data);

    if (strlen(user) > 0) {
        return do_crypto(1);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/Makefile
all: libtoken.so

libtoken.so: token.o crypto.o
	gcc -shared -o libtoken.so token.o crypto.o

token.o: src/token.c crypto.o
	gcc -fPIC -c src/token.c

crypto.o: src/crypto.c token.o
	gcc -fPIC -c src/crypto.c

clean:
	rm -f *.o *.so
EOF

    cat << 'EOF' > /home/user/app/api.py
import ctypes
import os
from flask import Flask, request, jsonify

app = Flask(__name__)
lib_path = os.path.join(os.path.dirname(__file__), 'libtoken.so')

try:
    libtoken = ctypes.CDLL(lib_path)
    libtoken.verify_token.argtypes = [ctypes.c_char_p]
    libtoken.verify_token.restype = ctypes.c_int
except OSError:
    libtoken = None

@app.route('/verify', methods=['POST'])
def verify():
    if not libtoken:
        return jsonify({"error": "libtoken not loaded"}), 500

    data = request.json.get('token', '')
    # serialize
    b_data = data.encode('utf-8')

    res = libtoken.verify_token(b_data)
    return jsonify({"result": "verified" if res else "failed"}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /home/user/app/metrics.py
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/stats', methods=['GET'])
def stats():
    return jsonify({"reqs": 100}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
pkill -f api.py
pkill -f metrics.py
python3 /home/user/app/api.py &
python3 /home/user/app/metrics.py &
EOF

    chmod +x /home/user/app/start_services.sh
    chmod -R 777 /home/user
