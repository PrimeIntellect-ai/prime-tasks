#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential expect netcat-openbsd openssh-server iproute2 curl
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the vendored package directory
    mkdir -p /app/microservice-gateway-1.2

    # Create the C source file with the specified perturbations
    cat << 'EOF' > /app/microservice-gateway-1.2/gateway.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>

void *http_server(void *arg) {
    int port = atoi(getenv("HTTP_PORT") ? getenv("HTTP_PORT") : "9001");
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);
    while(1) {
        int client_socket = accept(server_fd, NULL, NULL);
        char buffer[1024] = {0};
        read(client_socket, buffer, 1024);
        char *token = getenv("GATEWAY_TOKEN");
        char expected_auth[256];
        sprintf(expected_auth, "Authorization: Bearer %s", token ? token : "secure-micro-token");
        char *response;
        if (strstr(buffer, expected_auth) != NULL) {
            response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nGateway Active\n";
        } else {
            response = "HTTP/1.1 401 Unauthorized\r\n\r\n";
        }
        write(client_socket, response, strlen(response));
        close(client_socket);
    }
    return NULL;
}

int main() {
    int port = atoi(getenv("GETWAY_PORT") ? getenv("GETWAY_PORT") : "9000");
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        int client_socket = accept(server_fd, NULL, NULL);
        char buffer[1024] = {0};
        write(client_socket, "Username: ", 10);
        read(client_socket, buffer, 1024);
        buffer[strcspn(buffer, "\r\n")] = 0;
        if (strcmp(buffer, "admin") == 0) {
            write(client_socket, "Password: ", 10);
            memset(buffer, 0, 1024);
            read(client_socket, buffer, 1024);
            buffer[strcspn(buffer, "\r\n")] = 0;
            if (strcmp(buffer, "adminpass") == 0) {
                write(client_socket, "OK\n", 3);
                memset(buffer, 0, 1024);
                read(client_socket, buffer, 1024);
                buffer[strcspn(buffer, "\r\n")] = 0;
                if (strcmp(buffer, "ENABLE HTTP") == 0) {
                    pthread_t thread_id;
                    pthread_create(&thread_id, NULL, http_server, NULL);
                    write(client_socket, "HTTP ENABLED\n", 13);
                }
            }
        }
        close(client_socket);
    }
    return 0;
}
EOF

    # Create the Makefile with spaces instead of tabs (perturbation)
    cat << 'EOF' > /app/microservice-gateway-1.2/Makefile
gateway_daemon: gateway.c
    gcc -o gateway_daemon gateway.c -lpthread
EOF
    # Ensure spaces are used
    sed -i 's/^    /        /' /app/microservice-gateway-1.2/Makefile

    # Setup sshd
    mkdir -p /run/sshd
    ssh-keygen -A

    # Wrapper for pytest to start sshd for initial state tests
    mv /usr/local/bin/pytest /usr/local/bin/pytest.real
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
/usr/sbin/sshd
exec /usr/local/bin/pytest.real "$@"
EOF
    chmod +x /usr/local/bin/pytest

    chmod -R 777 /app
    chmod -R 777 /home/user
