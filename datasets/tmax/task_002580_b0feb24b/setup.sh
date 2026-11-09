#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gcc make curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /home/user/backend

    # Create corpus
    for i in $(seq 1 50); do
        echo -e "POST /process HTTP/1.1\r\nHost: localhost\r\n\r\nHello world $i" > /app/corpus/clean/req_$i.txt
        echo -e "POST /process HTTP/1.1\r\nHost: localhost\r\n\r\nHello world $i RECURSE_HALT foo" > /app/corpus/evil/req_$i.txt
    done

    # Create backend parser.c
    cat << 'EOF' > /home/user/backend/parser.c
#include <string.h>
#include <stdio.h>

void parse_body(char *body) {
    char *p = body;
    while (*p) {
        p += strspn(p, " \t\r\n");
        if (!*p) break;
        char *next = strpbrk(p, " \t\r\n");
        if (!next) next = p + strlen(p);
        char token[256];
        int len = next - p;
        if (len > 255) len = 255;
        strncpy(token, p, len);
        token[len] = '\0';

        if (strcmp(token, "RECURSE_HALT") == 0) {
            p -= 1; // BUG: Moves pointer backwards, causing infinite loop
        } else {
            p = next;
        }
    }
}
EOF

    # Create backend server.c
    cat << 'EOF' > /home/user/backend/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

extern void parse_body(char *body);

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(1);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9000);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(1);
    if (listen(server_fd, 3) < 0) exit(1);

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        char *body = strstr(buffer, "\r\n\r\n");
        if (body) {
            body += 4;
            parse_body(body);
        }

        char *response = "HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nPROCESSED";
        write(new_socket, response, strlen(response));
        close(new_socket);
    }
    return 0;
}
EOF

    # Create nginx.conf
    cat << 'EOF' > /home/user/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /process {
            proxy_pass http://127.0.0.1:9001;
        }
    }
}
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
gcc -o /home/user/backend/server /home/user/backend/server.c /home/user/backend/parser.c
/home/user/backend/server &
nginx -c /home/user/nginx.conf
EOF
    chmod +x /app/start_services.sh

    chmod -R 777 /home/user /app
