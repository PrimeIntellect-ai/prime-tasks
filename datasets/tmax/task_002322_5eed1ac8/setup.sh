#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest flask requests

    mkdir -p /app/backend

    # Create frontend script
    cat << 'EOF' > /app/frontend.py
from flask import Flask, request
import socket

app = Flask(__name__)

@app.route('/transform', methods=['POST'])
def transform():
    data = request.get_data()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 9090))
    s.sendall(data)
    result = s.recv(8192)
    s.close()
    return result

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    # Create backend C source
    cat << 'EOF' > /app/backend/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <math.h>

void transform(const char* in, char* out) {
    int len = strlen(in);
    int out_idx = 0;
    // Intentional off-by-one bug
    for (int i = 0; i <= len; i++) {
        int count = 1;
        while (i + 1 < len && in[i] == in[i+1]) {
            count++;
            i++;
        }
        out_idx += sprintf(out + out_idx, "%d%c", count, in[i]);
    }
}

void* handle_client(void* arg) {
    int sock = *(int*)arg;
    free(arg);
    char buffer[4096] = {0};
    char out_buffer[8192] = {0};
    int n = read(sock, buffer, sizeof(buffer)-1);
    if (n > 0) {
        transform(buffer, out_buffer);
        write(sock, out_buffer, strlen(out_buffer));
    }
    close(sock);
    return NULL;
}

int main() {
    // Dummy math usage to require -lm
    double dummy = pow(2.0, 2.0);

    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9090);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        int *client_sock = malloc(sizeof(int));
        *client_sock = new_socket;
        pthread_t thread_id;
        pthread_create(&thread_id, NULL, handle_client, (void*)client_sock);
        pthread_detach(thread_id);
    }
    return 0;
}
EOF

    # Create backend Makefile with missing linker flags
    cat << 'EOF' > /app/backend/Makefile
all: server

server: server.c
	gcc -o server server.c
EOF

    # Create start script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
cd /app/backend && ./server &
cd /app && python3 frontend.py &
EOF
    chmod +x /app/start.sh

    # Create sample files
    echo -n "aabbbc" > /app/sample_in.txt
    echo -n "2a3b1c" > /app/sample_out_expected.txt

    # Set permissions
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
