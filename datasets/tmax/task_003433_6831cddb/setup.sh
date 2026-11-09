#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest

    mkdir -p /app/edgetelem-1.2.0

    cat << 'EOF' > /app/edgetelem-1.2.0/server.c
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>

/* Missing stdlib.h intentionally */

int main() {
    char *port_str = getenv("TELEM_PORT");
    if (!port_str) port_str = "8080";
    /* Deliberate bug: multiplying port by 10 */
    int port = atoi(port_str) * 10;

    char *out_file = getenv("TELEM_OUT");
    if (!out_file) out_file = "telemetry.log";

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        return 1;
    }

    listen(server_fd, 3);

    while (1) {
        int new_socket = accept(server_fd, NULL, NULL);
        if (new_socket < 0) continue;

        char buffer[2048] = {0};
        read(new_socket, buffer, 2047);

        if (strncmp(buffer, "GET /ping", 9) == 0) {
            char *resp = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\npong\n";
            write(new_socket, resp, strlen(resp));
        } else if (strncmp(buffer, "POST /submit", 12) == 0) {
            char *body = strstr(buffer, "\r\n\r\n");
            if (body) {
                body += 4;
                FILE *f = fopen(out_file, "a");
                if (f) {
                    fputs(body, f);
                    fclose(f);
                }
            }
            char *resp = "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nok\n";
            write(new_socket, resp, strlen(resp));
        } else {
            char *resp = "HTTP/1.1 404 Not Found\r\n\r\n";
            write(new_socket, resp, strlen(resp));
        }
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/edgetelem-1.2.0/Makefile
CC = gcc
CFLAGS = -Wall -Werror=implicit-function-declaration

edgetelem: server.c
	$(CC) $(CFLAGS) -o edgetelem server.c

clean:
	rm -f edgetelem
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
