#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev nginx curl
    pip3 install pytest

    mkdir -p /home/user/deployment_test

    cat << 'EOF' > /home/user/deployment_test/backend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

// Returns 1 if version >= min_version, else 0.
// BUGGY IMPLEMENTATION: Naive string comparison
int check_version(const char* version, const char* min_version) {
    if (version == NULL) return 0;
    return strcmp(version, min_version) >= 0;
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
    address.sin_port = htons(9090);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }
    if (listen(server_fd, 10) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            continue;
        }
        read(new_socket, buffer, 1024);

        char *version_header = strstr(buffer, "X-API-Version: ");
        int authorized = 0;
        if (version_header) {
            char version[32] = {0};
            sscanf(version_header, "X-API-Version: %31s", version);
            // Trim carriage return if present
            char *cr = strchr(version, '\r');
            if (cr) *cr = '\0';
            authorized = check_version(version, "2.2.0");
        }

        char *response;
        if (authorized) {
            response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
        } else {
            response = "HTTP/1.1 426 Upgrade Required\r\nContent-Length: 16\r\n\r\nUpgrade Required";
        }
        write(new_socket, response, strlen(response));
        close(new_socket);
        memset(buffer, 0, sizeof(buffer));
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/deployment_test/test.sh
#!/bin/bash
# Test 1: Exact minimum version
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/api/2.2.0/deploy
# Test 2: Older version
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/api/2.1.9/deploy
# Test 3: Newer version that fails naive string sort
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/api/2.10.0/deploy
# Test 4: Major version upgrade
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/api/3.0.0/deploy
EOF

    chmod +x /home/user/deployment_test/test.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
