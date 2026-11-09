#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make curl wget
    pip3 install pytest

    # Create /app and generate the video artifact
    mkdir -p /app
    # Generate a 10s video at 30fps (300 frames) where exactly 7 frames (100 to 106) are RED
    ffmpeg -f lavfi -i color=c=black:s=320x240:r=30:d=10 -vf "drawbox=x=0:y=0:w=320:h=240:color=red:t=fill:enable='between(n,100,106)'" -c:v libx264 -y /app/ci_test_run.mp4

    # Create dashboard directory
    mkdir -p /home/user/dashboard

    # Create the buggy server.c
    cat << 'EOF' > /home/user/dashboard/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int weights[] = {10, 20, 30};
int values[] = {60, 100, 120};
int capacity = 50;

int calculate_optimal_score(int capacity, int weights[], int values[], int n) {
    // Flawed greedy algorithm
    int score = 0;
    int current_weight = 0;
    for (int i = 0; i < n; i++) {
        if (current_weight + weights[i] <= capacity) {
            current_weight += weights[i];
            score += values[i];
        }
    }
    return score;
}

void handle_request(int client_socket) {
    char raw_request[4096];
    int bytes_read = read(client_socket, raw_request, sizeof(raw_request) - 1);
    if (bytes_read > 0) {
        raw_request[bytes_read] = '\0';
    } else {
        close(client_socket);
        return;
    }

    char buffer[256];
    // Buffer overflow vulnerability
    strcpy(buffer, raw_request);

    char response[] = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}";
    write(client_socket, response, sizeof(response) - 1);
    close(client_socket);
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while (1) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        if (new_socket >= 0) {
            handle_request(new_socket);
        }
    }
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > /home/user/dashboard/Makefile
all:
	gcc -O0 -g -o server server.c

clean:
	rm -f server
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
