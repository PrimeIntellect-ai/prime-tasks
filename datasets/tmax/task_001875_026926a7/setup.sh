#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gcc make
    pip3 install pytest flask gunicorn

    mkdir -p /app/c_backend /app/flask_app

    # Create /app/c_backend/Makefile
    cat << 'EOF' > /app/c_backend/Makefile
all: validator

validator: validator.c
    gcc -o server validator.c
EOF

    # Create /app/c_backend/validator.c
    cat << 'EOF' > /app/c_backend/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

void delay() {
    volatile int dummy = 0;
    for(int i=0; i<10000000; i++) {
        dummy += i;
    }
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9000);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            continue;
        }
        read(new_socket, buffer, 1024);
        delay();
        char *response = "VALIDATED\n";
        send(new_socket, response, strlen(response), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    # Create /app/flask_app/legacy_crypto.js
    cat << 'EOF' > /app/flask_app/legacy_crypto.js
function validateSignature(resourceId, secret) {
    let hash = 0;
    let str = resourceId + secret;
    for (let i = 0; i < str.length; i++) {
        let char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash; // Convert to 32bit integer
    }
    return hash.toString(16);
}
EOF

    # Create /app/flask_app/app.py
    cat << 'EOF' > /app/flask_app/app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/')
def index():
    return "Hello World"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create /app/nginx.conf
    cat << 'EOF' > /app/nginx.conf
worker_processes 1;
daemon off;

events {
    worker_connections 1024;
}

http {
    server {
        listen 8080;

        location /api/ {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # Create /app/start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nginx -c /app/nginx.conf &
cd /app/flask_app && python3 app.py &
cd /app/c_backend && ./server &
wait
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
