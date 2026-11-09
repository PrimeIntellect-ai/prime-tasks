#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <arpa/inet.h>

#define PORT 8080
#define BUFFER_SIZE 2048

void generate_token(char *token) {
    // VULNERABILITY: Predictable token
    srand(12345); // Fixed seed for demonstration of predictability
    sprintf(token, "%d", rand());
}

void handle_client(int client_socket) {
    char buffer[BUFFER_SIZE];
    read(client_socket, buffer, BUFFER_SIZE - 1);

    if (strncmp(buffer, "GET /login", 10) == 0) {
        char *next = strstr(buffer, "next=");
        char redirect_url[256] = "/dashboard";
        if (next) {
            sscanf(next, "next=%255s", redirect_url);
            // Quick hack to remove HTTP protocol boundaries in simple parser
            char *space = strchr(redirect_url, ' ');
            if (space) *space = '\0';
        }

        char token[64];
        generate_token(token);

        char response[1024];
        // VULNERABILITY: Open Redirect
        sprintf(response, "HTTP/1.1 302 Found\r\n"
                          "Set-Cookie: AuthToken=%s\r\n"
                          "Location: %s\r\n\r\n", token, redirect_url);
        write(client_socket, response, strlen(response));
    } 
    else if (strncmp(buffer, "GET /rotate", 11) == 0) {
        char *user = strstr(buffer, "user=");
        char username[256] = "unknown";
        if (user) {
            sscanf(user, "user=%255s", username);
            char *space = strchr(username, ' ');
            if (space) *space = '\0';
        }

        char response[1024];
        // VULNERABILITY: XSS
        sprintf(response, "HTTP/1.1 400 Bad Request\r\n"
                          "Content-Type: text/html\r\n\r\n"
                          "<html><body>Rotation failed for user: %s</body></html>", username);
        write(client_socket, response, strlen(response));
    } else {
        char *response = "HTTP/1.1 404 Not Found\r\n\r\n";
        write(client_socket, response, strlen(response));
    }
    close(client_socket);
}

int main(int argc, char *argv[]) {
    int port = PORT;
    if (argc > 1) {
        port = atoi(argv[1]);
    }

    int server_fd, client_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

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
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }
    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((client_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            exit(EXIT_FAILURE);
        }
        handle_client(client_socket);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
