#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb strace curl redis-server nginx vim
    pip3 install pytest flask gunicorn redis

    mkdir -p /app/c2
    mkdir -p /home/user/interceptor

    # Create C2 Flask app
    cat << 'EOF' > /app/c2/app.py
from flask import Flask
import redis
import random
import string

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/get_key')
def get_key():
    key = ''.join(random.choices(string.hexdigits.lower()[:16], k=32))
    return key
EOF

    # Create Nginx config
    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx.conf
cd /app/c2 && gunicorn -w 4 -b 127.0.0.1:5000 app:app --daemon
EOF
    chmod +x /app/start_services.sh

    # Create malware source and compile
    cat << 'EOF' > /app/malware.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <string.h>
#include <time.h>

int main() {
    struct sockaddr_in server;
    int sock;
    char message[1000], server_reply[2000];

    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock == -1) return 1;

    server.sin_addr.s_addr = inet_addr("127.0.0.1");
    server.sin_family = AF_INET;
    server.sin_port = htons(8080);

    if (connect(sock, (struct sockaddr *)&server, sizeof(server)) < 0) return 1;

    sprintf(message, "GET /get_key HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n");
    if (send(sock, message, strlen(message), 0) < 0) return 1;

    srand(time(NULL) ^ getpid());
    if (rand() % 2 == 0) {
        usleep(6000);
        int *p = NULL;
        *p = 1; // Simulate race condition crash
    }

    if (recv(sock, server_reply, 2000, 0) < 0) return 1;

    close(sock);
    return 0;
}
EOF
    gcc /app/malware.c -o /app/malware.bin
    rm /app/malware.c

    # Create broken interceptor
    cat << 'EOF' > /home/user/interceptor/hook.c
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <string.h>

// Missing _GNU_SOURCE and dlfcn.h

typedef ssize_t (*orig_recv_type)(int sockfd, void *buf, size_t len, int flags);

ssize_t recv(int sockfd, void *buf, size_t len, int flags) {
    orig_recv_type orig_recv;
    orig_recv = (orig_recv_type)dlsym(RTLD_NEXT, "recv");

    ssize_t res = orig_recv(sockfd, buf, len, flags);

    if (res > 0) {
        // Simple extraction logic
        char *body = strstr((char*)buf, "\r\n\r\n");
        if (body) {
            body += 4;
            FILE *f = fopen("/home/user/extracted_keys.txt", "a");
            if (f) {
                fprintf(f, "%.32s\n", body);
                fclose(f);
            }
        }
    }
    return res;
}
EOF

    cat << 'EOF' > /home/user/interceptor/build.sh
#!/bin/bash
# Missing -fPIC -shared -ldl
gcc hook.c -o hook.so
EOF
    chmod +x /home/user/interceptor/build.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
