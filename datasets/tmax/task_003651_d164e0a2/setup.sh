#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server socat bubblewrap gcc
    pip3 install pytest flask requests

    # Create directories
    mkdir -p /app/gateway
    mkdir -p /app/backend
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create Gateway app
    cat << 'EOF' > /app/gateway/app.py
from flask import Flask, request, Response
import socket

app = Flask(__name__)

@app.route('/execute', methods=['POST'])
def execute():
    payload = request.get_data(as_text=True)
    # Currently forwards directly to localhost:9000
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 9000))
        s.sendall(payload.encode('utf-8'))
        s.shutdown(socket.SHUT_WR)
        resp = s.recv(4096)
        s.close()
        return Response(resp, status=200)
    except Exception as e:
        return Response(str(e), status=500)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    # Create Backend executor source and compile
    cat << 'EOF' > /app/backend/executor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        printf("Processed: %s\n", buffer);
    }
    return 0;
}
EOF
    gcc -o /app/backend/executor /app/backend/executor.c
    rm /app/backend/executor.c

    # Create Backend start script
    cat << 'EOF' > /app/backend/start_backend.sh
#!/bin/bash
socat TCP-LISTEN:9000,reuseaddr,fork EXEC:/app/backend/executor
EOF
    chmod +x /app/backend/start_backend.sh

    # Create start_all.sh script
    cat << 'EOF' > /app/start_all.sh
#!/bin/bash
redis-server --daemonize yes
/app/backend/start_backend.sh &
python3 /app/gateway/app.py &
wait
EOF
    chmod +x /app/start_all.sh

    # Generate Corpus
    for i in $(seq 1 50); do
        echo "--output=/tmp/out${i}.log status --verbose" > /app/corpus/clean/payload_${i}.txt
        echo "--log-file=/proc/self/environ --id=${i}" > /app/corpus/evil/payload_${i}.txt
    done

    # Set permissions
    chmod -R 777 /app

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
